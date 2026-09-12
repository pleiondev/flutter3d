/// `GraphicsDevice.overwriteTexture`, on the one backend a plain `flutter
/// test` can check content against without a GPU or a browser — `pro-eng-02`.
///
///     flutter test test/texture_overwrite_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

CpuDevice _device() =>
    CpuDevice(width: 8, height: 8, shaders: CpuShaderLibrary(builtinCpuShaders()));

TextureHandle _solidTexture(CpuDevice device, int width, int height, int rgba) {
  final pixels = ByteData(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    pixels.setUint32(i * 4, rgba, Endian.big);
  }
  return device.createTextureFromPixels(
    width: width,
    height: height,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: pixels,
  )!;
}

/// The RGBA at ([x], [y]) of [texture]'s own CPU pixels, as bytes 0-255.
List<int> _texelAt(CpuTexture texture, int x, int y) {
  final at = (y * texture.width + x) * 4;
  return <int>[
    for (var c = 0; c < 4; c++) (texture.pixels[at + c] * 255).round(),
  ];
}

void main() {
  test('a region overwrite changes only the texels it named', () async {
    final device = _device();
    final handle = _solidTexture(device, 4, 4, 0xFF0000FF); // red, opaque
    final texture = handle.backend as CpuTexture;

    final patch = ByteData(2 * 2 * 4);
    for (var i = 0; i < 4; i++) {
      patch.setUint32(i * 4, 0x00FF00FF, Endian.big); // green, opaque
    }
    await device.overwriteTexture(
      handle,
      patch,
      region: const ScreenRect(x: 1, y: 1, width: 2, height: 2),
    );

    // The 2x2 patch at (1,1) is green now...
    for (var y = 1; y < 3; y++) {
      for (var x = 1; x < 3; x++) {
        expect(_texelAt(texture, x, y), <int>[0, 255, 0, 255], reason: '($x,$y)');
      }
    }
    // ...and every texel outside it is still the original red.
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        if (x >= 1 && x < 3 && y >= 1 && y < 3) continue;
        expect(_texelAt(texture, x, y), <int>[255, 0, 0, 255], reason: '($x,$y)');
      }
    }
  });

  test('with no region, the whole base level is overwritten', () async {
    final device = _device();
    final handle = _solidTexture(device, 2, 2, 0xFF0000FF);
    final texture = handle.backend as CpuTexture;

    final patch = ByteData(2 * 2 * 4);
    for (var i = 0; i < 4; i++) {
      patch.setUint32(i * 4, 0x0000FFFF, Endian.big); // blue, opaque
    }
    await device.overwriteTexture(handle, patch);

    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 2; x++) {
        expect(_texelAt(texture, x, y), <int>[0, 0, 255, 255]);
      }
    }
  });

  test('refuses a format that is not one of readbackFormats', () async {
    final device = _device();
    final pixels = ByteData(4 * 4 * 4);
    final handle = device.createTextureFromPixels(
      width: 4,
      height: 4,
      format: TextureFormat.r16g16b16a16Float,
      pixels: ByteData(4 * 4 * 4 * 2),
    )!;
    expect(
      () => device.overwriteTexture(handle, pixels),
      throwsUnsupportedError,
    );
  });

  test('refuses a non-zero mip level', () async {
    final device = _device();
    final handle = _solidTexture(device, 4, 4, 0xFFFFFFFF);
    expect(
      () => device.overwriteTexture(handle, ByteData(4 * 4), mipLevel: 1),
      throwsUnsupportedError,
    );
  });

  test('refuses a region that runs past the end of a row, not just one '
      'past the end of the array', () async {
    // Mutation: drop the explicit bound check. A region this far out of
    // range — (2,2) sized 4x4 on a 4x4 texture — would still index past
    // the backing Float32List and throw a RangeError (a subtype of
    // ArgumentError, so `throwsArgumentError` would still pass for the
    // wrong reason); this test instead asks for a region that runs one
    // texel past the end of a row, which lands inside the *next* row of
    // the same, perfectly sized array — silent corruption of an unrelated
    // texel with no exception at all, which only the explicit check
    // catches.
    final device = _device();
    final handle = _solidTexture(device, 4, 4, 0xFFFFFFFF);
    expect(
      () => device.overwriteTexture(
        handle,
        ByteData(2 * 1 * 4),
        region: const ScreenRect(x: 3, y: 0, width: 2, height: 1),
      ),
      throwsArgumentError,
    );
  });

  test('refuses bytes that do not match the region', () async {
    final device = _device();
    final handle = _solidTexture(device, 4, 4, 0xFFFFFFFF);
    expect(
      () => device.overwriteTexture(
        handle,
        ByteData(4),
        region: const ScreenRect(width: 2, height: 2),
      ),
      throwsArgumentError,
    );
  });
}
