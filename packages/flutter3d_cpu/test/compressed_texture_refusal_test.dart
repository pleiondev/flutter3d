/// A compressed `TextureFormat` reaching this backend used to succeed
/// quietly — the size check compares against RGBA8's byte count, and every
/// real compressed format is smaller than that, so it read the block bytes
/// as raw texels and produced a texture full of noise, not an error.
///
/// This backend will never decode a block-compressed format: it samples raw
/// texels, and building a BC/ETC2/ASTC decoder for a software rasteriser
/// that exists to be fast in a test run is not a trade worth making. So the
/// refusal is now explicit and named, at the one call each upload path makes
/// before doing anything else.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

CpuDevice _device() => CpuDevice(
  width: 4,
  height: 4,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  test('createTextureFromPixels refuses a compressed format by name', () {
    final device = _device();
    // A real BC1 block for a 4x4 texture is 8 bytes; the point is that it
    // never gets far enough to check that — the format check runs first.
    final bytes = ByteData(8);
    expect(
      () => device.createTextureFromPixels(
        width: 4,
        height: 4,
        format: TextureFormat.bc1RGBAUNormInt,
        pixels: bytes,
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('TextureFormat.bc1RGBAUNormInt'),
        ),
      ),
    );
  });

  test('createCubeTextureFromPixels refuses a compressed format by name', () {
    final device = _device();
    final faces = List.generate(6, (_) => ByteData(8));
    expect(
      () => device.createCubeTextureFromPixels(
        size: 4,
        format: TextureFormat.etc2RGB8UNormInt,
        faces: faces,
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('TextureFormat.etc2RGB8UNormInt'),
        ),
      ),
    );
  });

  test('an uncompressed format is unaffected', () {
    final device = _device();
    final bytes = ByteData(4 * 4 * 4);
    expect(
      device.createTextureFromPixels(
        width: 4,
        height: 4,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: bytes,
      ),
      isNotNull,
    );
  });
}
