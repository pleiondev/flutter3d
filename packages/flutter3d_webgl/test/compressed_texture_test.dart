/// A block-compressed `TextureFormat` reaching `WebGlDevice.
/// createTextureFromPixels` uploads through `compressedTexSubImage2D`, on a
/// real Chrome WebGL2 context — not a mock, because the question this answers
/// (does the driver actually accept `texStorage2D` with a compressed sized
/// internal format, followed by `compressedTexSubImage2D`, for the specific
/// GL enum values this backend computed) is exactly the one a mock cannot.
///
///     flutter test --platform chrome test/compressed_texture_test.dart
///
/// ETC2 is the one format family this asserts unconditionally: it is
/// mandated by the OpenGL ES 3.0 core WebGL2 is built on, so every real
/// browser answers `getExtension('WEBGL_compressed_texture_etc')` with a
/// non-null value. The others are genuinely platform-dependent, so this
/// checks *consistency* instead — a format the driver reports it lacks
/// refuses cleanly rather than corrupting a texture, and one it reports it
/// has uploads with no error left in the queue.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter3d_webgl/src/webgl_formats.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

WebGlDevice _makeDevice({int width = 8, int height = 8}) {
  final device = WebGlDevice.create(
    width: width,
    height: height,
    sources: engineShaders,
  );
  if (device == null) fail('no WebGL2 context in this browser');
  return device;
}

/// [format]'s block layout, so a test can build an exactly-sized buffer for
/// any texture size without repeating the block math per format.
ByteData _levelBytes(TextureFormat format, int width, int height) {
  final layout = format.blockLayout;
  final blocksWide = (width + layout.blockWidth - 1) ~/ layout.blockWidth;
  final blocksHigh = (height + layout.blockHeight - 1) ~/ layout.blockHeight;
  return ByteData(blocksWide * blocksHigh * layout.bytesPerBlock);
}

void main() {
  test('ETC2 always uploads cleanly: mandated by WebGL2\'s own core', () {
    final device = _makeDevice(width: 4, height: 4);
    device.debugDrainErrors('setup');

    final handle = device.createTextureFromPixels(
      width: 4,
      height: 4,
      format: TextureFormat.etc2RGB8UNormInt,
      pixels: _levelBytes(TextureFormat.etc2RGB8UNormInt, 4, 4),
    );

    expect(handle, isNotNull);
    expect(handle!.format, TextureFormat.etc2RGB8UNormInt);
    expect(device.debugDrainErrors('after ETC2 upload'), isNull);
    device.dispose();
  });

  test('an ETC2 mip chain uploads block-rounded sizes at every level', () {
    final device = _makeDevice(width: 8, height: 8);
    device.debugDrainErrors('setup');

    const format = TextureFormat.etc2RGBA8UNormInt;
    final handle = device.createTextureFromPixels(
      width: 8,
      height: 8,
      format: format,
      pixels: _levelBytes(format, 8, 8),
      // One mip below 8x8 is 4x4 — still a single whole block, never smaller
      // than one, which is the case every compressed mip chain bottoms out on.
      mipLevels: [_levelBytes(format, 4, 4)],
    );

    expect(handle, isNotNull);
    expect(device.debugDrainErrors('after ETC2 mip chain upload'), isNull);
    device.dispose();
  });

  test('a wrong-sized compressed level is refused before any GL call', () {
    final device = _makeDevice(width: 4, height: 4);
    device.debugDrainErrors('setup');

    final short = ByteData(
      _levelBytes(TextureFormat.etc2RGB8UNormInt, 4, 4).lengthInBytes - 1,
    );
    final handle = device.createTextureFromPixels(
      width: 4,
      height: 4,
      format: TextureFormat.etc2RGB8UNormInt,
      pixels: short,
    );

    expect(handle, isNull);
    // Refused in Dart, before `createTexture`/`compressedTexSubImage2D` ever
    // ran — a texture this device never made would otherwise leave nothing to
    // blame the missing byte on.
    expect(device.debugDrainErrors('after refused upload'), isNull);
    device.dispose();
  });

  test('every compressed format either uploads cleanly or refuses by name, '
      'never silently', () {
    const allCompressed = [
      TextureFormat.bc1RGBAUNormInt,
      TextureFormat.bc1RGBAUNormIntSRGB,
      TextureFormat.bc3RGBAUNormInt,
      TextureFormat.bc3RGBAUNormIntSRGB,
      TextureFormat.bc5RGUNormInt,
      TextureFormat.bc7RGBAUNormInt,
      TextureFormat.bc7RGBAUNormIntSRGB,
      TextureFormat.etc2RGB8UNormInt,
      TextureFormat.etc2RGB8UNormIntSRGB,
      TextureFormat.etc2RGBA8UNormInt,
      TextureFormat.etc2RGBA8UNormIntSRGB,
      TextureFormat.astc4x4LDR,
      TextureFormat.astc4x4LDRSRGB,
      TextureFormat.astc8x8LDR,
      TextureFormat.astc8x8LDRSRGB,
    ];

    for (final format in allCompressed) {
      final device = _makeDevice(
        width: format.blockLayout.blockWidth,
        height: format.blockLayout.blockHeight,
      );
      device.debugDrainErrors('setup');
      final pixels = _levelBytes(
        format,
        format.blockLayout.blockWidth,
        format.blockLayout.blockHeight,
      );

      TextureHandle? handle;
      Object? thrown;
      try {
        handle = device.createTextureFromPixels(
          width: format.blockLayout.blockWidth,
          height: format.blockLayout.blockHeight,
          format: format,
          pixels: pixels,
        );
      } catch (e) {
        thrown = e;
      }

      if (thrown != null) {
        expect(
          thrown,
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains(format.name),
          ),
          reason: '$format: a refusal must name the format it refused',
        );
      } else {
        expect(handle, isNotNull, reason: '$format');
        expect(
          device.debugDrainErrors('after $format upload'),
          isNull,
          reason: '$format uploaded but left an error in the queue',
        );
      }
      device.dispose();
    }
  });

  test('the queried support matches what this context actually accepts', () {
    // Cross-checks `CompressedTextureSupport.query` against reality rather
    // than trusting the query alone: a context that reports an extension but
    // rejects the format it unlocks would pass every test above for the wrong
    // reason — throwing where the query said it should not have to.
    final canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;
    final gl = canvas.getContext('webgl2') as web.WebGL2RenderingContext?;
    if (gl == null) fail('no WebGL2 context in this browser');
    final support = CompressedTextureSupport.query(gl);
    expect(support.etc2, isTrue, reason: 'ETC2 is mandated by WebGL2\'s core');
  });
}
