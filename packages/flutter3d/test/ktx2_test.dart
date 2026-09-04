/// Proves the KTX2 reader against the specification, not against itself.
///
/// No `.ktx2` fixture files: the byte layout below is copied from the
/// official KTX2 specification and from `VkFormat`'s numbers in
/// `KhronosGroup/KTX-Software` (see `ktx2_format.dart`), assembled here by
/// hand field by field. A test that built a file with the loader's own writer
/// and then read it back with the loader would only prove internal
/// consistency; this proves the reader agrees with the format's actual
/// authors.
///
/// Runs off-device: everything is `ByteData` over a plain `Uint8List`, the
/// same property `f3d_test.dart` and `gpu_formats_test.dart` rely on.
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/assets/ktx2/ktx2.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/build_ktx2.dart';

void main() {
  test('a single-level BC7 texture reads its dimensions, format and bytes', () {
    final level = List<int>.generate(16, (i) => i);
    final texture = Ktx2Texture.parse(
      buildKtx2(
        vkFormat: VkFormat.bc7UNormBlock,
        pixelWidth: 4,
        pixelHeight: 4,
        levels: [level],
      ),
    );

    expect(texture.pixelWidth, 4);
    expect(texture.pixelHeight, 4);
    expect(texture.format, TextureFormat.bc7RGBAUNormInt);
    expect(texture.levels, hasLength(1));
    expect(
      texture.levels.single.buffer.asUint8List(
        texture.levels.single.offsetInBytes,
        texture.levels.single.lengthInBytes,
      ),
      level,
    );
  });

  test('a level is a view over the file, not a copy', () {
    // Two textures parsed over the same bytes; a write through one is visible
    // in the other only if both alias the file rather than having copied it.
    final encoded = buildKtx2();
    final first = Ktx2Texture.parse(encoded);
    final second = Ktx2Texture.parse(encoded);

    first.levels.single.setUint8(0, 0xFF);
    expect(
      second.levels.single.getUint8(0),
      0xFF,
      reason: 'the levels do not alias the file, so the loader copied',
    );
  });

  test('a three-level R8G8B8A8 mip chain keeps level order', () {
    final levels = [
      List<int>.filled(4, 0xAA), // level 0, base
      List<int>.filled(4, 0xBB), // level 1
      List<int>.filled(4, 0xCC), // level 2, smallest
    ];
    final texture = Ktx2Texture.parse(
      buildKtx2(vkFormat: VkFormat.r8g8b8a8UNorm, levels: levels),
    );

    expect(texture.format, TextureFormat.r8g8b8a8UNormInt);
    expect(texture.levels, hasLength(3));
    for (var i = 0; i < 3; i++) {
      expect(texture.levels[i].getUint8(0), levels[i][0]);
    }
  });

  test('a wrong magic is refused', () {
    final bytes = buildKtx2();
    bytes[0] = 0x00;
    expect(() => Ktx2Texture.parse(bytes), throwsA(isA<Ktx2FormatException>()));
  });

  test('a file truncated inside its last level is refused', () {
    final bytes = buildKtx2();
    final truncated = Uint8List.sublistView(bytes, 0, bytes.length - 4);
    expect(
      () => Ktx2Texture.parse(truncated),
      throwsA(isA<Ktx2FormatException>()),
    );
  });

  test('Zstandard supercompression names itself and is refused', () {
    final bytes = buildKtx2(
      supercompressionScheme: Ktx2SupercompressionScheme.zstandard,
    );
    expect(
      () => Ktx2Texture.parse(bytes),
      throwsA(
        isA<Ktx2FormatException>().having(
          (e) => e.message,
          'message',
          contains('Zstandard'),
        ),
      ),
    );
  });

  // An undefined vkFormat with no supercompression is not a curiosity: it is
  // precisely a UASTC file out of `toktx --uastc`, the likeliest non-ETC1S
  // thing anyone hands this reader. The message has to name it, and has to
  // call scheme 0 what the spec calls it. Mutation: dropping the
  // `Ktx2SupercompressionScheme.none` case from `_supercompressionName`
  // sends it back down the fallback, which reports `vendor scheme 0`, and
  // both the `none` and the `not vendor` expectations report false.
  test('a UASTC file names UASTC and calls supercompression 0 none', () {
    final bytes = buildKtx2(
      vkFormat: VkFormat.undefined,
      supercompressionScheme: Ktx2SupercompressionScheme.none,
    );
    expect(
      () => Ktx2Texture.parse(bytes),
      throwsA(
        isA<Ktx2FormatException>()
            .having((e) => e.message, 'message', contains('Basis Universal'))
            .having((e) => e.message, 'message', contains('UASTC'))
            .having((e) => e.message, 'message', contains('(none)'))
            .having((e) => e.message, 'message', isNot(contains('vendor'))),
      ),
    );
  });

  // The sampler must not decode, because the shader already does:
  // `surface.glsl` calls `SrgbToLinear` on the albedo texel and
  // `cpu_shaders_surface.dart` calls `toLinear` on it, unconditionally and on
  // every backend. An sRGB `TextureFormat` becomes a real sRGB sampler on
  // Impeller and WebGL2 and nothing at all on the rasteriser, so a file
  // written as `_SRGB` used to draw dark on two backends out of three from
  // bytes the third read right. Mutation: mapping any of these back to its
  // `...SRGB` engine format — the pairing this switch used to have — makes
  // the matching expectation report false.
  test('an sRGB vkFormat reads as the linear format with the same bits', () {
    TextureFormat formatOf(int vkFormat) =>
        Ktx2Texture.parse(buildKtx2(vkFormat: vkFormat)).format;

    expect(formatOf(VkFormat.bc7SrgbBlock), TextureFormat.bc7RGBAUNormInt);
    expect(
      formatOf(VkFormat.bc7SrgbBlock),
      formatOf(VkFormat.bc7UNormBlock),
      reason: 'the two carry identical blocks',
    );
    expect(formatOf(VkFormat.bc1RgbaSrgbBlock), TextureFormat.bc1RGBAUNormInt);
    expect(formatOf(VkFormat.bc3SrgbBlock), TextureFormat.bc3RGBAUNormInt);
    expect(
      formatOf(VkFormat.etc2R8g8b8SrgbBlock),
      TextureFormat.etc2RGB8UNormInt,
    );
    expect(
      formatOf(VkFormat.etc2R8g8b8a8SrgbBlock),
      TextureFormat.etc2RGBA8UNormInt,
    );
    expect(formatOf(VkFormat.astc4x4SrgbBlock), TextureFormat.astc4x4LDR);
    expect(formatOf(VkFormat.astc8x8SrgbBlock), TextureFormat.astc8x8LDR);
    expect(formatOf(VkFormat.r8g8b8a8Srgb), TextureFormat.r8g8b8a8UNormInt);
    expect(formatOf(VkFormat.b8g8r8a8Srgb), TextureFormat.b8g8r8a8UNormInt);
  });

  test('an unknown vkFormat names its number and is refused', () {
    final bytes = buildKtx2(vkFormat: 999999);
    expect(
      () => Ktx2Texture.parse(bytes),
      throwsA(
        isA<Ktx2FormatException>().having(
          (e) => e.message,
          'message',
          contains('999999'),
        ),
      ),
    );
  });

  test('a texture array (layerCount > 0) is refused', () {
    final bytes = buildKtx2(layerCount: 2);
    expect(() => Ktx2Texture.parse(bytes), throwsA(isA<Ktx2FormatException>()));
  });

  test('a cube map (faceCount == 6) is refused', () {
    final bytes = buildKtx2(faceCount: 6);
    expect(() => Ktx2Texture.parse(bytes), throwsA(isA<Ktx2FormatException>()));
  });

  test('a 3D texture (pixelDepth > 0) is refused', () {
    final bytes = buildKtx2(pixelDepth: 2);
    expect(() => Ktx2Texture.parse(bytes), throwsA(isA<Ktx2FormatException>()));
  });

  test('levelCount == 0 (runtime mip generation) is refused', () {
    final bytes = buildKtx2(levels: const []);
    expect(() => Ktx2Texture.parse(bytes), throwsA(isA<Ktx2FormatException>()));
  });

  // The key/value section was read by nothing at all, so each of these three
  // used to load and then draw wrong — upside down, channel-shuffled, or
  // darkened at every translucent texel — with no message anywhere.
  // Mutation for the group: deleting the `_checkKeyValues(bytes, view)` call
  // in `Ktx2Texture.parse` makes all four parse without complaint, and the
  // three refusals report false.
  group('key/value data', () {
    test('the default orientation, and only it, is accepted', () {
      expect(
        Ktx2Texture.parse(
          buildKtx2(
            keyValues: const <String, String>{
              'KTXorientation': 'rd',
              'KTXwriter': 'a test',
            },
          ),
        ).format,
        TextureFormat.bc7RGBAUNormInt,
      );
    });

    test('a bottom-up orientation is refused by name', () {
      expect(
        () => Ktx2Texture.parse(
          buildKtx2(keyValues: const <String, String>{'KTXorientation': 'ru'}),
        ),
        throwsA(
          isA<Ktx2FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('KTXorientation'), contains('"ru"')),
          ),
        ),
      );
    });

    test('a swizzle is refused by name', () {
      expect(
        () => Ktx2Texture.parse(
          buildKtx2(keyValues: const <String, String>{'KTXswizzle': 'bgra'}),
        ),
        throwsA(
          isA<Ktx2FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('KTXswizzle'), contains('"bgra"')),
          ),
        ),
      );
    });

    test('premultiplied alpha is refused by name', () {
      expect(
        () => Ktx2Texture.parse(
          buildKtx2(
            keyValues: const <String, String>{'KTXpremultipliedAlpha': ''},
          ),
        ),
        throwsA(
          isA<Ktx2FormatException>().having(
            (e) => e.message,
            'message',
            contains('KTXpremultipliedAlpha'),
          ),
        ),
      );
    });
  });

  test('isKtx2File recognises the identifier and nothing else', () {
    expect(isKtx2File(buildKtx2()), isTrue);
    expect(isKtx2File(Uint8List.fromList([1, 2, 3, 4])), isFalse);
    expect(isKtx2File(Uint8List(0)), isFalse);
  });
}
