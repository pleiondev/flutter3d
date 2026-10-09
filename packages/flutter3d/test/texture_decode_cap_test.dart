/// `A4.16`/`A4.17`: an image goes to a device that decodes it itself when
/// there is one, and is held to a size cap at decode whichever path it takes.
///
/// Off-device: the browser half is stood in for by a device that records
/// what it was asked, and the CPU half by decoders that hand back known
/// pixels. What a real browser does with `createImageBitmap` is the WebGL2
/// and WebGPU backends' to show in a browser run.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/src/engine/assets/texture_upload.dart';
import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// A PNG's signature and IHDR, which is all [encodedImageSize] reads.
Uint8List _pngHeader(int width, int height) {
  final bytes = Uint8List(33);
  bytes.setAll(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  ByteData.sublistView(bytes)
    ..setUint32(8, 13)
    ..setUint32(16, width)
    ..setUint32(20, height);
  bytes.setAll(12, 'IHDR'.codeUnits);
  return bytes;
}

/// [width] by [height] of one grey level, so any average of it is that level.
Rgba8Image _flat(int width, int height, int level) => Rgba8Image(
  width: width,
  height: height,
  pixels: Uint8List(width * height * 4)
    ..fillRange(0, width * height * 4, level),
);

/// A device that decodes images itself, as the browser backends do, and
/// records what it was asked. Every other member is unreachable here.
final class _DecodingDevice extends GraphicsDevice with EncodedImageUpload {
  _DecodingDevice({this.maxTexture = 8192});

  /// Whether the platform decode refuses; never, since the per-call cap is
  /// the only cap left (the process-wide one went in 1.0).
  final bool refuses = false;
  final int maxTexture;
  final List<({bool mipmaps, int? maxDimension})> asked =
      <({bool mipmaps, int? maxDimension})>[];

  @override
  DeviceLimits get limits => DeviceLimits(maxTextureDimension2D: maxTexture);

  @override
  DeviceFeatures get features => FakeBackend().features;

  @override
  Future<TextureHandle?> decodeTexture(
    Uint8List encoded, {
    bool mipmaps = false,
    int? maxDimension,
  }) async {
    asked.add((mipmaps: mipmaps, maxDimension: maxDimension));
    if (refuses) return null;
    return wrapTexture(
      backend: Object(),
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
    );
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw StateError('${invocation.memberName} is not part of this test');
}

void main() {
  group('cappedImageSize', () {
    test('keeps an image that fits, and the aspect of one that does not', () {
      expect(cappedImageSize(512, 256, maxDimension: 1024), (
        width: 512,
        height: 256,
      ));
      expect(cappedImageSize(4096, 2048, maxDimension: 1024), (
        width: 1024,
        height: 512,
      ));
      expect(cappedImageSize(4096, 16, maxDimension: 1024), (
        width: 1024,
        height: 4,
      ));
      expect(cappedImageSize(100000, 1, maxDimension: 1024), (
        width: 1024,
        height: 1,
      ));
      expect(cappedImageSize(4096, 4096), (width: 4096, height: 4096));
    });
  });

  test('encodedImageSize reads a PNG header and nothing it does not know', () {
    expect(encodedImageSize(_pngHeader(640, 480)), (width: 640, height: 480));
    expect(encodedImageSize(Uint8List.fromList(List<int>.filled(40, 7))), null);
  });

  test('fitRgba8Image averages the texels each output texel covers', () {
    final image = Rgba8Image(
      width: 4,
      height: 2,
      pixels: Uint8List.fromList(<int>[
        for (var i = 0; i < 8; i++) ...<int>[i.isEven ? 0 : 200, 0, 0, 255],
      ]),
    );
    final fitted = fitRgba8Image(image, maxDimension: 2);
    expect((fitted.width, fitted.height), (2, 1));
    expect(fitted.pixels, <int>[100, 0, 0, 255, 100, 0, 0, 255]);
    expect(identical(fitRgba8Image(image, maxDimension: 8), image), isTrue);
  });

  test('a device that decodes images is handed the bytes, capped', () async {
    final device = _DecodingDevice();
    Future<Rgba8Image?> never(Uint8List encoded) =>
        throw StateError('the device decoded it');

    final handle = await uploadEncodedImage(
      device,
      _pngHeader(4, 4),
      decodeImage: never,
      sampling: const TextureSampling(useMipmaps: true),
      maxDimension: 1024,
    );

    expect(handle, isNotNull);
    expect(device.asked.single, (mipmaps: true, maxDimension: 1024));
  });

  test('the device limit caps the decode when no cap is asked', () async {
    final device = _DecodingDevice(maxTexture: 2048);
    await uploadEncodedImage(
      device,
      _pngHeader(4, 4),
      decodeImage: (_) async => null,
    );
    expect(device.asked.single.maxDimension, 2048);
  });

  test('platformDecode false and a refusal both reach the CPU decoder', () {
    final device = FakeBackend();
    // FakeBackend is not an EncodedImageUpload: the CPU path, held to the cap.
    return uploadEncodedImage(
      device,
      _pngHeader(8, 4),
      decodeImage: (_) async => _flat(8, 4, 90),
      maxDimension: 4,
      platformDecode: false,
    ).then((handle) {
      expect(handle, isNotNull);
      final spec = device.uploadedTextures.single;
      expect((spec.width, spec.height), (4, 2));
      expect(device.uploadedPixels.single.getUint8(0), 90);
    });
  });

  test('a SizedImageDecoder is asked for the capped size', () async {
    final device = FakeBackend();
    final asked = <int?>[];
    Future<Rgba8Image?> sized(Uint8List encoded, {int? maxDimension}) async {
      asked.add(maxDimension);
      return _flat(2, 2, 10);
    }

    await uploadEncodedImage(
      device,
      _pngHeader(2, 2),
      decodeImage: sized,
      maxDimension: 512,
    );
    expect(asked, <int?>[512]);
  });
}
