/// The read side of the plugin boundary: the built-in readers are
/// `ModelDecoder`s, a name alone says whether a file can be read, and an
/// application's own decoder is asked before any built-in one.
///
///     dart test test/model_decoder_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

/// A decoder claiming every file with [suffix], the way an application adds
/// a format — or replaces one.
final class _Claims implements ModelDecoder {
  const _Claims(this.suffix);

  final String suffix;

  @override
  bool handles(String fileName, Uint8List bytes) => fileName.endsWith(suffix);

  @override
  Future<ModelDocument> decode(
    Uint8List bytes,
    ModelLoadRequest request,
    AssetUriResolver resolveUri,
  ) async =>
      const PlainModelDocument(warnings: <String>['read by the application']);
}

final class _Named extends AssetSource {
  const _Named(this.name);

  final String name;

  @override
  String get key => 'memory:$name';

  @override
  Future<Uint8List> read() async => Uint8List(0);

  @override
  AssetUriResolver get resolveUri =>
      (AssetRequest request) async => throw StateError('no siblings here');
}

void main() {
  final nothing = Uint8List(0);

  group('the built-in readers', () {
    test('every suffix the table names reaches a reader that claims it', () {
      // Mutation: add a suffix to `builtInModelExtensions` whose reader does
      // not answer to it. The drop guard would let the file through and the
      // reader it lands on would not recognise it.
      for (final MapEntry<String, ModelFormat> each
          in builtInModelExtensions.entries) {
        final decoder = builtInModelDecoder(
          each.value,
          ModelLoadRequest(source: _Named('x${each.key}')),
        );
        expect(
          decoder.handles('part${each.key}', nothing),
          isTrue,
          reason: each.key,
        );
      }
    });

    test('a reader does not claim another format\'s suffix', () {
      expect(GltfLoader().handles('part.obj', nothing), isFalse);
      expect(ObjLoader().handles('part.glb', nothing), isFalse);
      expect(const F3dDecoder().handles('part.stl', nothing), isFalse);
    });
  });

  group('canDecodeFileName', () {
    test('a built-in suffix is enough', () {
      expect(canDecodeFileName('helmet.GLB'), isTrue);
    });

    test('a suffix nobody reads is not', () {
      expect(canDecodeFileName('scan.ply'), isFalse);
    });

    test('an application\'s decoder adds its own suffix', () {
      // Mutation: ask `recognizedModelFormat` alone. A format the application
      // taught `decodeModel` to read would still be turned away at a window.
      expect(
        canDecodeFileName(
          'scan.ply',
          decoders: const <ModelDecoder>[_Claims('.ply')],
        ),
        isTrue,
      );
    });
  });

  test('an application\'s decoder is asked before the built-in reader for a '
      'suffix that reader owns', () async {
    final document = await decodeModelBytes(
      const ModelLoadRequest(
        source: _Named('part.stl'),
        decoders: <ModelDecoder>[_Claims('.stl')],
      ),
      nothing,
      (AssetRequest request) async => throw StateError('no siblings here'),
    );
    expect(document.warnings, <String>['read by the application']);
  });
}
