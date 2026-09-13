/// `ap-07` in `doc/asset-pipeline-plan.md`'s real-hardware half: a file
/// `flutter3d_formats`'s own BC1/BC3/ETC2 encoders wrote, sampled on a real
/// WebGL2 context, not by this port's own test decoders.
///
/// **Why this lives here and not in `flutter3d_formats`.** The encoders
/// themselves stay Flutter-free — that is the entire point of `ap-01` and
/// `ap-07` living in `flutter3d_formats` — but sampling their output on a
/// real GPU needs a `GraphicsDevice`, which needs the Flutter SDK. This
/// package already runs on a real WebGL2 context headlessly (`flutter test
/// --platform chrome`), which is cheaper to run here than booting an Impeller
/// application the way `ap-06`'s own real-hardware check does, so it is
/// where this lives — a dev dependency on `flutter3d_formats`, nothing `lib/`
/// reaches.
///
/// **What this catches that `flutter3d_formats`'s own tests cannot.** ETC2's
/// column-major pixel numbering and two-plane index word are exactly the
/// kind of bit-order choice a self-written decoder can get wrong in a way
/// that agrees with itself — `etc2_test_decoder.dart` proves the encoder
/// against its own understanding of the format, and a driver decoding the
/// same bytes is the only thing that proves that understanding is the
/// specification's.
///
///     flutter test --platform chrome test/formats_encoder_conformance_test.dart
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

WebGlDevice _makeDevice({int width = 8, int height = 8}) {
  final device = WebGlDevice.create(
    width: width,
    height: height,
    sources: engineShaders,
  );
  if (device == null) fail('no WebGL2 context in this browser');
  return device;
}

/// Draws a full-viewport triangle sampling [texture] at the constant UV
/// `(u, v)` — every vertex carries the same UV, so the fragment shader's
/// interpolated coordinate is that point regardless of where on screen it
/// lands, the same technique `flutter3d_conformance`'s
/// `checkCompressedTextureSamples` uses to read one point of a block-
/// compressed texture without a full sampling harness.
Future<List<int>> _sampleAt(
  GraphicsDevice device,
  TextureHandle texture,
  double u,
  double v,
) async {
  const size = 8;
  final vertex = device.shaders['ParticleVertex'];
  final fragment = device.shaders['ParticleTextured'];
  if (vertex == null || fragment == null) {
    fail('the textured particle stages are missing');
  }

  final target = device.createTexture(
    const RenderTargetSpec(
      width: size,
      height: size,
      format: TextureFormat.r8g8b8a8UNormInt,
    ),
  );
  final triangle = Float32List.fromList(<double>[
    -1, -1, 0.5, 1, 1, 1, 1, u, v,
    3, -1, 0.5, 1, 1, 1, 1, u, v,
    -1, 3, 0.5, 1, 1, 1, 1, u, v,
  ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2]);

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
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    ..bindPipeline(device.createPipeline(vertex, fragment))
    ..bindUniformBlock(vertex, 'ParticleInfo', <String, Float32List>{
      'view_projection': Float32List.fromList(Matrix4.identity().storage),
    })
    ..bindUniformBlock(fragment, 'FogInfo', <String, Float32List>{
      'fog': Float32List(4),
      'eye': Float32List(4),
    })
    ..bindTexture(fragment, 'particle_texture', texture)
    ..bindVertexData(ByteData.sublistView(triangle), 3)
    ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
    ..draw();
  pass.submit();

  final read = await device.readPixels(target);
  if (read == null) fail('the target could not be read back');
  final bytes = read.buffer.asUint8List();
  final at = ((size ~/ 2) * size + size ~/ 2) * 4;
  return <int>[bytes[at], bytes[at + 1], bytes[at + 2]];
}

/// An 8×4 image, two 4×4 blocks: a solid orange-red left, a solid teal
/// right — distinct colours a real encoder's general (non-solid) path
/// produces two different base colours and tables for, unlike the single
/// hand-built block `flutter3d_conformance` already checks.
Rgba8Image _twoBlockImage() {
  final pixels = Uint8List(8 * 4 * 4);
  for (var y = 0; y < 4; y++) {
    for (var x = 0; x < 8; x++) {
      final at = (y * 8 + x) * 4;
      final left = x < 4;
      pixels[at] = left ? 220 : 20;
      pixels[at + 1] = left ? 90 : 170;
      pixels[at + 2] = left ? 30 : 190;
      pixels[at + 3] = 255;
    }
  }
  return Rgba8Image(width: 8, height: 4, pixels: pixels);
}

void main() {
  final source = _twoBlockImage();

  Future<void> checkTwoBlocks(TextureFormat format, Uint8List encoded) async {
    final device = _makeDevice();
    if (!device.supportsTextureFormat(format)) {
      markTestSkipped('${format.name} not reported as supported here');
      device.dispose();
      return;
    }
    final texture = device.createTextureFromPixels(
      width: 8,
      height: 4,
      format: format,
      pixels: ByteData.sublistView(encoded),
    );
    expect(texture, isNotNull);

    final left = await _sampleAt(device, texture!, 0.25, 0.5);
    final right = await _sampleAt(device, texture, 0.75, 0.5);
    for (final (channel, l, r, wantL, wantR) in <(String, int, int, int, int)>[
      ('red', left[0], right[0], source.red(0, 0), source.red(4, 0)),
      ('green', left[1], right[1], source.green(0, 0), source.green(4, 0)),
      ('blue', left[2], right[2], source.blue(0, 0), source.blue(4, 0)),
    ]) {
      expect(
        (l - wantL).abs(),
        lessThanOrEqualTo(24),
        reason: '${format.name} left block $channel: got $l, encoded $wantL',
      );
      expect(
        (r - wantR).abs(),
        lessThanOrEqualTo(24),
        reason: '${format.name} right block $channel: got $r, encoded $wantR',
      );
    }
    device.dispose();
  }

  test('a real BC1 file samples both its blocks\' colours on a real GPU', () async {
    await checkTwoBlocks(TextureFormat.bc1RGBAUNormInt, encodeBc1(source));
  });

  test('a real BC3 file samples both its blocks\' colours on a real GPU', () async {
    await checkTwoBlocks(TextureFormat.bc3RGBAUNormInt, encodeBc3(source));
  });

  test('a real ETC2 RGB8 file samples both its blocks\' colours on a real GPU', () async {
    await checkTwoBlocks(TextureFormat.etc2RGB8UNormInt, encodeEtc2Rgb8(source));
  });
}
