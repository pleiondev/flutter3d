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
///
/// **This used to allocate the six faces and never look at one.** It asserted
/// that a handle came back, that it called itself a cube, that it reported six
/// slices, and that five faces were refused — every one of which a backend with
/// its face table transposed passes, which is the single thing the check is
/// named for. The colours were built and thrown away. Three files cited it as
/// what catches a transposed pair while it could not have caught one, and
/// `checkUniformMemberMismatchIsRefused` already named it in its own doc as the
/// check that passed by construction.
Future<void> checkCubeFaces(GraphicsDevice device) async {
  if (!device.supportsCubeTextures) {
    // Not a failure: the interface says to ask, and a device that answers false
    // is entitled to. What would be a failure is answering true and then not
    // doing it, which is what everything below checks.
    return;
  }

  const size = 4;
  // Every channel is 0 or 255, and that is arithmetic rather than taste: the
  // cube-sky stage decodes its texel from sRGB, and those two values are the
  // only ones the decode maps onto themselves. Any other colour would come back
  // shifted and the tolerance would have to hide it.
  const colours = <List<int>>[
    <int>[255, 0, 0],
    <int>[0, 255, 0],
    <int>[0, 0, 255],
    <int>[255, 255, 0],
    <int>[255, 0, 255],
    <int>[0, 255, 255],
  ];
  const names = <String>['+X', '−X', '+Y', '−Y', '+Z', '−Z'];

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

  // Everything above holds the *allocation*. What follows is the rule this
  // check is named for, and the only part a transposed face table can fail.
  final vertex = device.shaders['SkyCubeVertex'];
  final fragment = device.shaders['SkyCube'];
  require(
    vertex != null && fragment != null,
    'the cube-sky stages are missing, so no direction can be pointed at a '
    'face',
  );
  final pipeline = device.createPipeline(vertex!, fragment!);

  // The six axes, in the order `createCubeTextureFromPixels` documents its
  // faces. Written on all three corners of the triangle, so the interpolated
  // ray is the same everywhere and the answer cannot depend on which end of a
  // target row zero is.
  const axes = <List<double>>[
    <double>[1, 0, 0],
    <double>[-1, 0, 0],
    <double>[0, 1, 0],
    <double>[0, -1, 0],
    <double>[0, 0, 1],
    <double>[0, 0, -1],
  ];
  final indices = Uint16List.fromList(<int>[0, 1, 2]);

  for (var face = 0; face < 6; face++) {
    final target = device.createTexture(
      const RenderTargetSpec(
        width: size,
        height: size,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
    );
    final triangle = Float32List.fromList(<double>[
      for (final corner in const <List<double>>[
        <double>[-1, -1],
        <double>[3, -1],
        <double>[-1, 3],
      ]) ...<double>[...corner, ...axes[face], 1, 1, 1, 1],
    ]);

    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(
            texture: target,
            loadAction: LoadAction.clear,
            // Grey, so a draw that never happened is told apart from a face
            // whose colour is black in some channel.
            clearValue: Vector4(0.5, 0.5, 0.5, 1.0),
          ),
        ],
      ),
    );
    pass
      ..setPrimitiveType(PrimitiveType.triangle)
      ..setCullMode(CullMode.none)
      ..bindPipeline(pipeline)
      ..bindTexture(
        fragment,
        'sky_texture',
        cube,
        sampler: SamplerOptions.linearClamp,
      )
      ..bindVertexData(ByteData.sublistView(triangle), 3)
      ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
      ..draw()
      ..submit();

    final read = await device.readPixels(target);
    require(read != null, 'the target could not be read back');
    final bytes = read!.buffer.asUint8List();
    final at = ((size ~/ 2) * size + size ~/ 2) * 4;
    final got = <int>[bytes[at], bytes[at + 1], bytes[at + 2]];

    bool matches(List<int> want) =>
        got.indexed.every(((int, int) c) => (c.$2 - want[c.$1]).abs() <= 8);

    // Naming the face whose colour did arrive is the whole diagnostic: a
    // transposition reads as "you got −Y where +Y was asked for", which says
    // which two entries of the upload table changed places.
    //
    // Mutation: swap the `+Y` and `−Y` arms of `BoundTexture.sampleCube`'s
    // face table in `flutter3d_cpu`. The check then reports "a ray down +Y
    // sampled [255, 255, 0] ... That is face 3, −Y", which is the transposed
    // sky this exists for and which nothing else in the repository catches on
    // a hardware backend.
    final landed = colours.indexWhere(matches);
    require(
      matches(colours[face]),
      'a ray down ${names[face]} sampled $got where ${colours[face]} was '
      'uploaded as face $face. '
      '${landed < 0 ? 'That is no face\'s colour, so the cube was not sampled '
                'at all.' : 'That is face $landed, ${names[landed]} — two '
                'entries of the upload table have changed places.'} '
      'The order is +X, −X, +Y, −Y, +Z, −Z; see '
      'GraphicsDevice.createCubeTextureFromPixels.',
    );
  }
}
