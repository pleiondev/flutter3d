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
/// This container reader stops at `vkFormat` — a raw Khronos number, not a
/// `TextureFormat` — so it needs no Flutter SDK and this suite runs under
/// plain `dart test`. `flutter3d/test/ktx2_test.dart` covers the two things
/// that live above this line: the `vkFormat` -> `TextureFormat` mapping and
/// the unknown-`vkFormat` rejection that mapping is what performs — `ap-01`
/// in `doc/asset-pipeline-plan.md`.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

import 'helpers/build_ktx2.dart';

void main() {
  test(
    'a single-level BC7 texture reads its dimensions, vkFormat and bytes',
    () {
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
      expect(texture.vkFormat, VkFormat.bc7UNormBlock);
      expect(texture.levels, hasLength(1));
      expect(
        texture.levels.single.buffer.asUint8List(
          texture.levels.single.offsetInBytes,
          texture.levels.single.lengthInBytes,
        ),
        level,
      );
    },
  );

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

    expect(texture.vkFormat, VkFormat.r8g8b8a8UNorm);
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

  // An undefined vkFormat says "Basis Universal" and leaves the kind to the
  // data format descriptor. This file has none, so nothing says — it used to
  // be *guessed* to be UASTC and refused as such; UASTC is read now
  // (`uastc_test.dart`), and what is left to refuse is the file that does not
  // say. The message has to name what would have been read, and has to call
  // scheme 0 what the spec calls it. Mutation: dropping the
  // `Ktx2SupercompressionScheme.none` case from `_supercompressionName`
  // sends it back down the fallback, which reports `vendor scheme 0`, and
  // both the `none` and the `not vendor` expectations report false.
  test('an undefined vkFormat with no descriptor says what it would have '
      'read, and calls supercompression 0 none', () {
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

  // The mapping from an unrecognised `vkFormat` to a rejection lives above
  // this package, in `flutter3d`'s thin wrapper — this container stage reads
  // whatever number the file names and leaves interpreting it to a caller
  // with a `GraphicsDevice` to check it against.
  test(
    'an unrecognised vkFormat is accepted; interpreting it is a caller\'s job',
    () {
      final texture = Ktx2Texture.parse(buildKtx2(vkFormat: 999999));
      expect(texture.vkFormat, 999999);
    },
  );

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
    // A section with two entries in it, so this also pins the walk itself and
    // not only the three refusals: `KTXwriter` is what every real file
    // carries, and it must be stepped over rather than tripped on. Mutation:
    // dropping the `at = (at + 3) & ~3` padding step at the end of
    // `_checkKeyValues`'s loop misreads the second entry's length and this
    // reports false.
    test('the default orientation, and only it, is accepted', () {
      expect(
        Ktx2Texture.parse(
          buildKtx2(
            keyValues: const <String, String>{
              'KTXorientation': 'rd',
              'KTXwriter': 'a test',
            },
          ),
        ).vkFormat,
        VkFormat.bc7UNormBlock,
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
