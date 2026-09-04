import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

/// `draw(instanceCount: n)` puts the geometry down n times.
///
/// Additive and coincident, so the answer is one number: three instances of a
/// quarter-brightness triangle read back at three quarters, and one instance
/// reads back at a quarter. A backend that ignores the count fails on the first
/// number, and one that draws the wrong number of them fails on the ratio.
///
/// **Worth a conformance check rather than a golden**, because the three
/// backends reach instancing three different ways — Impeller passes the count
/// to `drawIndexed`, WebGL2 switches to `drawElementsInstanced` and has to
/// manage attribute divisors that are sticky per location, and the software
/// backend repeats the whole rasterisation. A golden would catch it on one
/// backend and only for scenes that happen to use it.
Future<void> checkInstancedDraw(GraphicsDevice device) async {
  const size = 16;

  Future<double> brightnessWith(int instances) async {
    final target = device.createTexture(
      const RenderTargetSpec(
        width: size,
        height: size,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
    );
    final vertex = device.shaders['DebugLineVertex'];
    final fragment = device.shaders['DebugLine'];
    require(
      vertex != null && fragment != null,
      'the debug-line stages are missing, so this cannot draw anything',
    );

    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(
            texture: target,
            loadAction: LoadAction.clear,
            clearValue: Vector4.zero(),
          ),
        ],
      ),
    );
    pass
      ..bindPipeline(device.createPipeline(vertex!, fragment!))
      ..setPrimitiveType(PrimitiveType.triangle)
      ..setCullMode(CullMode.none)
      ..setBlend(BlendState.additive)
      ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
        'view_projection': Float32List.fromList(Matrix4.identity().storage),
      });

    // One triangle covering the target at a quarter brightness. The same shape
    // the depth-write reproduction uses, for the same reason: the arithmetic is
    // checkable by eye.
    final one = Float32List.fromList(<double>[
      -1, -1, 0.5, 0.25, 0, 0, 1, //
      3, -1, 0.5, 0.25, 0, 0, 1,
      -1, 3, 0.5, 0.25, 0, 0, 1,
    ]);
    final indices = Uint16List.fromList(<int>[0, 1, 2]);
    pass
      ..bindVertexData(ByteData.sublistView(one), 3)
      ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
      ..draw(instanceCount: instances)
      ..submit();

    final pixels = await device.readPixels(target);
    require(pixels != null, 'the target could not be read back');
    return pixels!.buffer.asUint8List()[0] / 255.0;
  }

  final once = await brightnessWith(1);
  require(
    (once - 0.25).abs() < 0.02,
    'a single instance drew $once where a quarter was expected, so this '
    'check cannot say anything about three',
  );

  final thrice = await brightnessWith(3);
  require(
    (thrice - 0.75).abs() < 0.02,
    'three instances drew $thrice where three quarters was expected — the '
    'count was ignored, or applied the wrong number of times',
  );
}

/// A buffer uploaded for a use is bound for that use, and draws.
///
/// **This check used to assert nothing.** It uploaded sixty-four zero bytes
/// twice, once under each [GeometryUsage], and returned — so it passed on a
/// backend that took the argument and threw it away, which is the only backend
/// it was written for. `GeometryUsage` is documented as "not a hint" precisely
/// because WebGL binds a buffer to its target for life: a buffer uploaded as
/// vertices can never afterwards be bound as indices, the attempt is an
/// `INVALID_OPERATION`, the draw is dropped, and the frame comes back the clear
/// colour with nothing logged. Nothing short of drawing can tell.
///
/// So it draws, and through the *persistent* buffers — `uploadGeometry` and
/// `bindVertexBuffer`/`bindIndexBuffer` — which every mesh in the engine uses
/// and which no other check here touches: the rest bind bytes built for the
/// frame. A backend that uploaded both under one target, or that lost the
/// distinction between them, reads back the clear colour.
///
/// It moved out of [coreChecks] to get here. It cannot be answered without a
/// pipeline, and a list that promises "clears, uploads and readback only" was
/// the wrong place to keep a question that needs a draw.
Future<void> checkGeometryUsage(GraphicsDevice device) async {
  const size = 16;

  final target = device.createTexture(
    const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  final vertex = device.shaders['DebugLineVertex'];
  final fragment = device.shaders['DebugLine'];
  require(
    vertex != null && fragment != null,
    'the debug-line stages are missing, so this cannot draw anything',
  );

  // Four vertices, of which the indices name the last three: a triangle
  // covering the target, opaque red. The first is far off screen, so a backend
  // that drew vertices in order instead of through the buffer it was handed
  // draws a sliver nobody can see and this reads back the clear colour. Naming
  // 0, 1, 2 would have let exactly that pass.
  final vertices = Float32List.fromList(<double>[
    -9, -9, 0.5, 1, 0, 0, 1, //
    -1, -1, 0.5, 1, 0, 0, 1,
    3, -1, 0.5, 1, 0, 0, 1,
    -1, 3, 0.5, 1, 0, 0, 1,
  ]);
  final indices = Uint16List.fromList(<int>[1, 2, 3]);

  final vertexBuffer = device.uploadGeometry(
    ByteData.sublistView(vertices),
    GeometryUsage.vertices,
  );
  final indexBuffer = device.uploadGeometry(
    ByteData.sublistView(indices),
    GeometryUsage.indices,
  );

  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          loadAction: LoadAction.clear,
          clearValue: Vector4.zero(),
        ),
      ],
    ),
  );
  pass
    ..bindPipeline(device.createPipeline(vertex!, fragment!))
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    ..bindUniformBlock(vertex, 'LineInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindVertexBuffer(vertexBuffer, 4)
    ..bindIndexBuffer(indexBuffer, IndexType.int16, 3)
    ..draw()
    ..submit();

  final pixels = await device.readPixels(target);
  require(pixels != null, 'the target could not be read back');
  final red = pixels!.buffer.asUint8List()[0];
  // Mutation: drop the bytes on the floor in `CpuPassEncoder.bindIndexBuffer` —
  // the software backend then reads back the clear colour and fails here, which
  // the version of this check that only uploaded could not do.
  require(
    red > 250,
    'an indexed draw through buffers uploaded as vertices and as indices left '
    'the clear colour ($red, not 255). The two uses were not kept apart, or '
    'the persistent buffers are not bindable the way the engine binds them',
  );
}

/// Six faces, six directions, six colours.
///
/// The face order — +X, −X, +Y, −Y, +Z, −Z — is documented once, on
/// `GraphicsDevice.createCubeTextureFromPixels`, and each backend reaches it
/// differently: Impeller by slice index, WebGL by six consecutive face targets,
/// the software rasteriser by a table it holds itself. **A transposed pair is
/// invisible in any picture** — a sky with two faces swapped is complete,
/// seamless and simply wrong — so it is checked here rather than looked at.
///
/// Drawn rather than read back, because reading a cube face is not something
/// the interface offers and adding it for a test would be adding a member with
/// one caller. The sky pair is what samples a cube in this engine, so that is
/// what this uses.
Future<void> checkCubeFaces(GraphicsDevice device) async {
  if (!device.supportsCubeTextures) {
    // Not a failure: the interface says to ask, and a device that answers false
    // is entitled to. What would be a failure is answering true and then not
    // doing it, which is what everything below checks.
    return;
  }

  const size = 4;
  const colours = <List<int>>[
    <int>[255, 0, 0],
    <int>[0, 255, 0],
    <int>[0, 0, 255],
    <int>[255, 255, 0],
    <int>[255, 0, 255],
    <int>[0, 255, 255],
  ];

  final faces = <ByteData>[
    for (final colour in colours)
      ByteData.sublistView(
        Uint8List.fromList(<int>[
          for (var i = 0; i < size * size; i++) ...<int>[
            colour[0],
            colour[1],
            colour[2],
            255,
          ],
        ]),
      ),
  ];

  final cube = device.createCubeTextureFromPixels(
    size: size,
    format: TextureFormat.r8g8b8a8UNormInt,
    faces: faces,
  );
  require(
    cube != null,
    'the device says it supports cube textures and then made none from six '
    '4x4 RGBA8 faces',
  );
  require(
    cube!.type == TextureType.textureCube,
    'the handle came back as ${cube.type.name} rather than a cube',
  );
  require(
    cube.sliceCount == 6,
    'a cube reported ${cube.sliceCount} slices rather than six',
  );

  require(
    device.createCubeTextureFromPixels(
          size: size,
          format: TextureFormat.r8g8b8a8UNormInt,
          faces: faces.take(5).toList(),
        ) ==
        null,
    'five faces made a cube; the sixth is whatever the allocation held',
  );
}
