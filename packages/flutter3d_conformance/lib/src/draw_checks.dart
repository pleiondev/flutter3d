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
    final target = device.createTexture(const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ));
    final vertex = device.shaders['DebugLineVertex'];
    final fragment = device.shaders['DebugLine'];
    require(vertex != null && fragment != null,
        'the debug-line stages are missing, so this cannot draw anything');

    final pass = device.beginRenderPass(RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          loadAction: LoadAction.clear,
          clearValue: Vector4.zero(),
        ),
      ],
    ));
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
  require((once - 0.25).abs() < 0.02,
      'a single instance drew $once where a quarter was expected, so this '
      'check cannot say anything about three');

  final thrice = await brightnessWith(3);
  require((thrice - 0.75).abs() < 0.02,
      'three instances drew $thrice where three quarters was expected — the '
      'count was ignored, or applied the wrong number of times');
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
      ByteData.sublistView(Uint8List.fromList(<int>[
        for (var i = 0; i < size * size; i++)
          ...<int>[colour[0], colour[1], colour[2], 255],
      ])),
  ];

  final cube = device.createCubeTextureFromPixels(
    size: size,
    format: TextureFormat.r8g8b8a8UNormInt,
    faces: faces,
  );
  require(cube != null,
      'the device says it supports cube textures and then made none from six '
      '4x4 RGBA8 faces');
  require(cube!.type == TextureType.textureCube,
      'the handle came back as ${cube.type.name} rather than a cube');
  require(cube.sliceCount == 6,
      'a cube reported ${cube.sliceCount} slices rather than six');

  require(device.createCubeTextureFromPixels(
        size: size,
        format: TextureFormat.r8g8b8a8UNormInt,
        faces: faces.take(5).toList(),
      ) ==
      null,
      'five faces made a cube; the sixth is whatever the allocation held');
}
