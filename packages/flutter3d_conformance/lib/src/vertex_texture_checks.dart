import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

/// Whether a **vertex** stage can sample a texture.
///
/// **A probe rather than a requirement, and the distinction is the point.**
/// Nothing this engine draws today samples anything in a vertex stage. The
/// question is asked because it decides how morph targets get onto the GPU: the
/// vertex layout here is structural — the `in` declarations of `mesh.vert` are
/// the layout, one layout for every model — so morphing without a texture read
/// means a second layout and a second vertex shader per lighting model, while
/// morphing with one means deltas in a texture indexed by vertex id and no
/// layout change at all.
///
/// What each backend was expected to say, before it said it: WebGL2 yes, by
/// specification — GLES 3.0 requires at least sixteen vertex texture units. The
/// software rasteriser yes, because it is our own code and the only question is
/// whether it was written. flutter_gpu unknown, and an unknown that no amount
/// of reading the header settles.
///
/// The probe stage passes what it sampled straight through to the fragment
/// stage, so the pixel read back is the texture's own colour when the read
/// happened and the clear colour when it did not. A fragment stage doing its
/// own sampling would come back correct on a backend where the vertex stage
/// read nothing, which is exactly the answer being separated out.
Future<void> checkVertexTextureSampling(GraphicsDevice device) async {
  const size = 8;

  final vertex = device.shaders['VertexTextureProbeVertex'];
  final fragment = device.shaders['VertexTextureProbe'];
  require(
    vertex != null && fragment != null,
    'the vertex-texture probe stages are missing from the bundle',
  );

  // One texel, and a colour no clear in this file uses: red at three quarters,
  // so a partial read or a swizzle is a different number rather than a
  // plausible one.
  final pixels = ByteData(4)
    ..setUint8(0, 191)
    ..setUint8(1, 0)
    ..setUint8(2, 0)
    ..setUint8(3, 255);
  final texture = device.createTextureFromPixels(
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: pixels,
  );
  require(texture != null, 'a one-texel texture could not be uploaded');

  final target = device.createTexture(
    const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );

  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          loadAction: LoadAction.clear,
          // Green, so a frame that comes back unpainted is unmistakable
          // against a probe looking for red.
          clearValue: Vector4(0.0, 1.0, 0.0, 1.0),
        ),
      ],
    ),
  );

  // Position alone: the probe's vertex layout is one `in vec3`, which is the
  // smallest thing that can be drawn and keeps the check about the sampling.
  final triangle = Float32List.fromList(<double>[
    -1, -1, 0.5, //
    3, -1, 0.5,
    -1, 3, 0.5,
  ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2]);

  pass
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    ..bindPipeline(device.createPipeline(vertex!, fragment!))
    ..bindUniformBlock(vertex, 'ProbeInfo', <String, Float32List>{
      'at': Float32List.fromList(<double>[0.5, 0.5, 0.0, 0.0]),
    })
    // **The whole check is this line**: a texture bound to the *vertex* stage.
    ..bindTexture(vertex, 'probe_texture', texture!)
    ..bindVertexData(ByteData.sublistView(triangle), 3)
    ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
    ..draw()
    ..submit();

  final read = await device.readPixels(target);
  require(read != null, 'the target could not be read back');

  final bytes = read!.buffer.asUint8List();
  final red = bytes[0];
  final green = bytes[1];

  require(
    green < 32,
    'the frame came back the clear colour, so the draw never landed — which '
    'says nothing about vertex sampling on its own. Check that the probe '
    'pipeline links before reading this as a no.',
  );
  require(
    (red - 191).abs() <= 2,
    'the vertex stage sampled $red where 191 was in the texture. A vertex '
    'stage that cannot read a texture is not a fault — it is an answer, and '
    'it means morph targets on this backend need a vertex layout rather than '
    'a delta texture. Record it rather than fixing it.',
  );
}
