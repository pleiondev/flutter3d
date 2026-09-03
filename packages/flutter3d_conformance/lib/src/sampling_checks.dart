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

/// A trilinear sampler asking for more taps than the device has binds, draws
/// and reads back the texel it was pointed at.
///
/// **Two requests, and the second is the one that matters.** Sixteen is what
/// the engine's own documentation tells a caller to ask for anywhere, so it is
/// checked; but sixteen is also what every desktop Metal, Vulkan and Chrome
/// context answers to `maxAnisotropy`, so a request of sixteen never reaches a
/// clamp and a backend that forwarded the number untouched would pass. The
/// second request is `maxAnisotropy * 2` — above the ceiling by construction,
/// on any device, including the software rasteriser answering one.
///
/// **Not a check of the filtering** — a two-texel texture sampled at a texel
/// centre comes back the same with one tap or sixteen, and that is the point:
/// what is being asked is whether the bind is accepted at all. The
/// `anisotropic-floor` golden is where the filtering itself is looked at.
///
/// What a failure means differs by backend, which is why this is here rather
/// than in one backend's tests. flutter_gpu clamps inside its own bind and
/// throws only below one. WebGL2 raises `INVALID_VALUE` for a parameter above
/// the extension's ceiling and drops the call, leaving the taps as they were —
/// so the picture survives and only the error queue records it, which is why
/// `packages/flutter3d_webgl/test/anisotropy_test.dart` reads that queue and
/// this check cannot. The software rasteriser answers one and ignores the
/// field.
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

  /// The white texel, drawn through a sampler asking for [taps] of them.
  Future<int> centreThrough(int taps) async {
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
      // **The whole check is this sampler.** Whatever the device answered —
      // the contract says the backend clamps.
      ..bindTexture(
        fragment,
        'particle_texture',
        texture!,
        sampler: SamplerOptions.trilinearRepeat.withAnisotropy(taps),
      )
      ..bindVertexData(ByteData.sublistView(triangle), 3)
      ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
      ..draw();
    pass.submit();

    final read = await device.readPixels(target);
    require(read != null, 'the target could not be read back at $taps taps');
    return read!.buffer.asUint8List()[((size ~/ 2) * size + size ~/ 2) * 4];
  }

  // Above the ceiling by construction, whatever the ceiling is. A device
  // answering one gets two, a desktop answering sixteen gets thirty-two.
  final beyond = device.maxAnisotropy * 2;
  for (final taps in <int>[16, beyond]) {
    final red = await centreThrough(taps);
    require(
      red > 128,
      'a trilinear sampler asking for $taps-way anisotropy did not draw: the '
      'centre came back r=$red where the white texel was expected. The device '
      'answers maxAnisotropy ${device.maxAnisotropy}; a request above that is '
      'clamped by the backend, never refused. See ARCHITECTURE.md §7.2.',
    );
  }
}
