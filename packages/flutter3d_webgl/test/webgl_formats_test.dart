/// `textureFormatToGl` and `compressedTextureFormatToGl` — pure functions over
/// enums and booleans, no GL context touched, but still `@TestOn('browser')`:
/// `webgl_formats.dart` imports `package:web`, and that library does not
/// compile under the VM at all (`dart:js_interop` members like `.toJS` are
/// resolved by the web compilers only) — a plain `flutter test` fails to even
/// load this file. No file like this existed before compressed formats
/// needed one; see the doc comment on [textureFormatToGl] for the
/// throw-rather-than-degrade rule both are held to.
@TestOn('browser')
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgl/src/webgl_formats.dart';
import 'package:flutter_test/flutter_test.dart';

const compressed = {
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
  TextureFormat.astc4x4HDR,
  TextureFormat.astc8x8HDR,
};

const noSupport = CompressedTextureSupport(
  etc2: false,
  s3tc: false,
  s3tcSrgb: false,
  rgtc: false,
  bptc: false,
  astc: false,
);

const fullSupport = CompressedTextureSupport(
  etc2: true,
  s3tc: true,
  s3tcSrgb: true,
  rgtc: true,
  bptc: true,
  astc: true,
);

void main() {
  group('textureFormatToGl', () {
    test('throws for every compressed format', () {
      for (final format in compressed) {
        expect(
          () => textureFormatToGl(format),
          throwsUnsupportedError,
          reason: '$format',
        );
      }
    });

    test('throws for the formats with no sized internal format at all', () {
      for (final format in [
        TextureFormat.unknown,
        TextureFormat.a8UNormInt,
        TextureFormat.b8g8r8a8UNormInt,
        TextureFormat.b8g8r8a8UNormIntSRGB,
        TextureFormat.s8UInt,
      ]) {
        expect(
          () => textureFormatToGl(format),
          throwsUnsupportedError,
          reason: '$format',
        );
      }
    });

    test('resolves every other format', () {
      for (final format in TextureFormat.values) {
        if (compressed.contains(format)) continue;
        if ([
          TextureFormat.unknown,
          TextureFormat.a8UNormInt,
          TextureFormat.b8g8r8a8UNormInt,
          TextureFormat.b8g8r8a8UNormIntSRGB,
          TextureFormat.s8UInt,
        ].contains(format)) {
          continue;
        }
        expect(
          () => textureFormatToGl(format),
          returnsNormally,
          reason: '$format',
        );
      }
    });
  });

  group('compressedTextureFormatToGl', () {
    test('throws ArgumentError for an uncompressed format', () {
      expect(
        () => compressedTextureFormatToGl(
          TextureFormat.r8g8b8a8UNormInt,
          fullSupport,
        ),
        throwsArgumentError,
      );
    });

    test(
      'resolves every compressed format when every extension is present',
      () {
        for (final format in compressed) {
          if (format == TextureFormat.astc4x4HDR ||
              format == TextureFormat.astc8x8HDR) {
            continue;
          }
          expect(
            () => compressedTextureFormatToGl(format, fullSupport),
            returnsNormally,
            reason: '$format',
          );
        }
      },
    );

    test('ASTC HDR has no WebGL2 extension, ever', () {
      for (final format in [
        TextureFormat.astc4x4HDR,
        TextureFormat.astc8x8HDR,
      ]) {
        expect(
          () => compressedTextureFormatToGl(format, fullSupport),
          throwsUnsupportedError,
          reason: '$format',
        );
      }
    });

    test('names the missing extension when support is absent', () {
      final cases = <TextureFormat, String>{
        TextureFormat.bc1RGBAUNormInt: 'WEBGL_compressed_texture_s3tc',
        TextureFormat.bc1RGBAUNormIntSRGB: 'WEBGL_compressed_texture_s3tc_srgb',
        TextureFormat.bc3RGBAUNormInt: 'WEBGL_compressed_texture_s3tc',
        TextureFormat.bc3RGBAUNormIntSRGB: 'WEBGL_compressed_texture_s3tc_srgb',
        TextureFormat.bc5RGUNormInt: 'EXT_texture_compression_rgtc',
        TextureFormat.bc7RGBAUNormInt: 'EXT_texture_compression_bptc',
        TextureFormat.bc7RGBAUNormIntSRGB: 'EXT_texture_compression_bptc',
        TextureFormat.etc2RGB8UNormInt: 'WEBGL_compressed_texture_etc',
        TextureFormat.etc2RGB8UNormIntSRGB: 'WEBGL_compressed_texture_etc',
        TextureFormat.etc2RGBA8UNormInt: 'WEBGL_compressed_texture_etc',
        TextureFormat.etc2RGBA8UNormIntSRGB: 'WEBGL_compressed_texture_etc',
        TextureFormat.astc4x4LDR: 'WEBGL_compressed_texture_astc',
        TextureFormat.astc4x4LDRSRGB: 'WEBGL_compressed_texture_astc',
        TextureFormat.astc8x8LDR: 'WEBGL_compressed_texture_astc',
        TextureFormat.astc8x8LDRSRGB: 'WEBGL_compressed_texture_astc',
      };
      cases.forEach((format, extension) {
        expect(
          () => compressedTextureFormatToGl(format, noSupport),
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.message,
              'message',
              allOf(contains(format.name), contains(extension)),
            ),
          ),
          reason: '$format',
        );
      });
    });

    test('every GL enum value is distinct', () {
      final values = compressed
          .where(
            (f) =>
                f != TextureFormat.astc4x4HDR && f != TextureFormat.astc8x8HDR,
          )
          .map((f) => compressedTextureFormatToGl(f, fullSupport))
          .toList();
      expect(values.toSet(), hasLength(values.length));
    });
  });
}
