/// `fmt-29d`'s own row: the skeleton. `FbxDecoder` recognises an FBX file
/// and refuses to decode one, with a clear reason — the reader (`fmt-24`/
/// `fmt-25`) has not landed yet.
///
///     dart test test/fbx_decoder_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

Uint8List _binaryFbxHeader() => Uint8List.fromList(<int>[
  ...utf8.encode('Kaydara FBX Binary  '),
  0x00,
  0x1a,
  0x00,
  // A version number and some padding — not a real file, just enough of
  // one for `handles` to recognise.
  0xe8, 0x03, 0x00, 0x00,
]);

Uint8List _asciiFbxHeader() =>
    Uint8List.fromList(utf8.encode('; FBX 7.4.0 project file\n; ---\n'));

/// The bare minimum [AssetSource] `decode` never actually reads —
/// [FbxDecoder.decode] refuses before touching either of its other two
/// arguments, so this only has to satisfy the type.
final class _FakeAssetSource extends AssetSource {
  const _FakeAssetSource(this.key);

  @override
  final String key;

  @override
  Future<Uint8List> read() async =>
      throw UnsupportedError('not read in this test');

  @override
  AssetUriResolver get resolveUri =>
      (AssetRequest request) async =>
          throw UnsupportedError('no siblings in this test');
}

void main() {
  group('FbxDecoder.handles', () {
    const decoder = FbxDecoder();

    test('a binary FBX file, by its own magic', () {
      expect(decoder.handles('character.dat', _binaryFbxHeader()), isTrue);
    });

    test('an ASCII FBX file, by its own header comment', () {
      expect(decoder.handles('character.dat', _asciiFbxHeader()), isTrue);
    });

    test('anything named .fbx, whatever its bytes are', () {
      expect(
        decoder.handles('character.fbx', Uint8List.fromList(<int>[1, 2, 3])),
        isTrue,
      );
    });

    test('a glTF file is not an FBX file', () {
      final glb = Uint8List.fromList(
        utf8.encode(
          'glTF'
          '\x02\x00\x00\x00',
        ),
      );
      expect(decoder.handles('model.glb', glb), isFalse);
    });

    test('an empty file names nothing', () {
      expect(decoder.handles('model.dat', Uint8List(0)), isFalse);
    });
  });

  group('FbxDecoder.decode', () {
    const decoder = FbxDecoder();

    test('refuses every file with a clear reason, not a crash', () async {
      final source = const _FakeAssetSource('a.fbx');
      await expectLater(
        () => decoder.decode(
          _binaryFbxHeader(),
          ModelLoadRequest(source: source),
          source.resolveUri,
        ),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains('fmt-24'),
          ),
        ),
      );
    });
  });
}
