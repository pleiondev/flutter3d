/// A sampler asking for more than the device has is clamped, not refused.
///
/// `SamplerOptions.anisotropy` is documented as "ask for sixteen anywhere":
/// flutter_gpu clamps to `maxSamplerAnisotropy` inside its bind, WebGL2 raises
/// `INVALID_VALUE` for a parameter above the extension's ceiling and the
/// backend has to clamp it first, and the software rasteriser answers one and
/// ignores the field. Three different mechanisms behind one promise, which is
/// the shape of thing this suite exists for — a backend that forwarded the
/// number unclamped would pass every other check and drop the bind on the one
/// device with a lower ceiling.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

/// Sixteen-way anisotropy on a trilinear sampler binds, draws and reads back
/// the texel it was pointed at.
///
/// **Not a check of the filtering** — a two-texel texture sampled at a texel
/// centre comes back the same with one tap or sixteen, and that is the point:
/// what is being asked is whether the bind is accepted at all, on a device
/// that may allow less than sixteen. The `anisotropic-floor` golden is where
/// the filtering itself is looked at.
///
/// Trilinear on purpose. flutter_gpu refuses anisotropy above one on any
/// filter that is not linear, and the engine's constructor asserts the same,
/// so this is the one sampler shape the field is ever set on.
Future<void> checkAnisotropicSamplerAccepted(GraphicsDevice device) async {
  const size = 8;

  final vertex = device.shaders['ParticleVertex'];
  // The textured particle stage, for the reason `checkNullSamplerRepeats`
  // gives: the plain one never reads the texture it is handed.
  final fragment = device.shaders['ParticleTextured'];
  require(
    vertex != null && fragment != null,
    'the textured particle stages are missing, so nothing here samples',
  );

  // Black then white, side by side. Sampled at u = 0.75 — the centre of the
  // second texel — a bind that landed comes back white; one that was dropped
  // leaves the clear colour.
  final pixels = ByteData(2 * 1 * 4);
  for (var i = 0; i < 4; i++) {
    pixels.setUint8(i, i == 3 ? 255 : 0);
    pixels.setUint8(4 + i, 255);
  }
  final texture = device.createTextureFromPixels(
    width: 2,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: pixels,
  );
  require(texture != null, 'a two-texel texture could not be uploaded');

  final target = device.createTexture(
    const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );

  final triangle = Float32List.fromList(<double>[
    -1, -1, 0.5, 1, 1, 1, 1, 0.75, 0.5, //
    3, -1, 0.5, 1, 1, 1, 1, 0.75, 0.5,
    -1, 3, 0.5, 1, 1, 1, 1, 0.75, 0.5,
  ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2]);

  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          loadAction: LoadAction.clear,
          clearValue: Vector4(0.0, 1.0, 0.0, 1.0),
        ),
      ],
    ),
  );
  pass
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    ..bindPipeline(device.createPipeline(vertex!, fragment!))
    ..bindUniformBlock(vertex, 'ParticleInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindUniformBlock(fragment, 'FogInfo', <String, Float32List>{
      'fog': Float32List(4),
      'eye': Float32List(4),
    })
    // **The whole check is this sampler.** Sixteen, whatever the device
    // answered — the contract says the backend clamps.
    ..bindTexture(
      fragment,
      'particle_texture',
      texture!,
      sampler: SamplerOptions.trilinearRepeat.withAnisotropy(16),
    )
    ..bindVertexData(ByteData.sublistView(triangle), 3)
    ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
    ..draw();
  pass.submit();

  final read = await device.readPixels(target);
  require(read != null, 'the target could not be read back');
  final bytes = read!.buffer.asUint8List();
  final at = ((size ~/ 2) * size + size ~/ 2) * 4;
  final red = bytes[at];

  require(
    red > 128,
    'a trilinear sampler asking for sixteen-way anisotropy did not draw: the '
    'centre came back r=$red where the white texel was expected. The device '
    'answers maxAnisotropy ${device.maxAnisotropy}; a request above that is '
    'clamped by the backend, never refused. See ARCHITECTURE.md §7.2.',
  );
}
