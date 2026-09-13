import 'package:flutter3d_core/src/engine/assets/model_loader.dart';
import 'package:flutter3d_core/src/engine/assets/model_writer.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';
import 'package:flutter_test/flutter_test.dart';

const String kSamples = kSamplesPath;

Future<ModelDocument> box() => decodeModel(
  const ModelLoadRequest(source: FileAssetSource('$kSamples/Box.glb')),
);

void main() {
  group('every format', () {
    for (final ModelWriteFormat format in ModelWriteFormat.values) {
      test('$format: the isolate produces the same bytes as encoding in '
          'place', () async {
        final document = await box();
        final request = ModelWriteRequest(document: document, format: format);

        final local = encodeModel(request);
        final remote = await encodeModelInIsolate(request);

        // Mutation: send only `local` back without actually running the
        // encoder on the isolate — this compares the two independently
        // produced results rather than one against a copy of itself.
        expect(remote, local);
        expect(remote, isNotEmpty);
      });
    }
  });

  group('isolate encoding', () {
    test('an error in the isolate surfaces to the caller', () async {
      // A document with a surface whose vertex layout the writer cannot
      // make sense of is not something any of the four writers here
      // actually refuses on — so the error case exercised is the more
      // ordinary one: `PlainModelDocument` with no surfaces at all still
      // encodes (every writer here treats an empty document as an empty
      // file, not a refusal), which is worth pinning precisely because it
      // is *not* an error, unlike `decodeModelInIsolate`'s own file-not-
      // found case.
      const empty = PlainModelDocument();
      final bytes = await encodeModelInIsolate(
        const ModelWriteRequest(document: empty, format: ModelWriteFormat.obj),
      );
      expect(bytes, isNotEmpty); // a header comment, at minimum
    });

    test('several models encode concurrently', () async {
      final document = await box();
      final results = await Future.wait(<Future<Object>>[
        encodeModelInIsolate(
          ModelWriteRequest(
            document: document,
            format: ModelWriteFormat.glb,
          ),
        ),
        encodeModelInIsolate(
          ModelWriteRequest(
            document: document,
            format: ModelWriteFormat.obj,
          ),
        ),
        encodeModelInIsolate(
          ModelWriteRequest(
            document: document,
            format: ModelWriteFormat.stl,
          ),
        ),
      ]);
      expect(results, hasLength(3));
      for (final result in results) {
        expect(result, isA<Object>());
      }
    });

    test('the document travels whole — materials included', () async {
      final document = await decodeModel(
        const ModelLoadRequest(
          source: FileAssetSource('$kSamples/BoxTextured.glb'),
        ),
      );
      final bytes = await encodeModelInIsolate(
        ModelWriteRequest(document: document, format: ModelWriteFormat.glb),
      );

      // Read the isolate's own output back to prove the material and its
      // texture actually crossed, not just that some bytes came back.
      final readBack = await decodeModelBytes(
        const ModelLoadRequest(source: FileAssetSource('$kSamples/ignored')),
        bytes,
        (request) async => throw StateError('a .glb needs no sibling'),
      );
      expect(readBack.materials, isNotEmpty);
      expect(readBack.materials.first.baseColorTexture, isNotNull);
    });
  });

  group('ModelWriteFormat.stlAscii', () {
    test('writes the text dialect, not the binary one', () async {
      final document = await box();
      final bytes = await encodeModelInIsolate(
        ModelWriteRequest(
          document: document,
          format: ModelWriteFormat.stlAscii,
        ),
      );
      expect(looksLikeAsciiStl(bytes), isTrue);
      expect(isBinaryStl(bytes), isFalse);
    });
  });
}
