/// "Download as…" with no database: the engine's writers through the
/// isolate, the `.gltf` taken apart from a GLB, and the cache in front of
/// them — handed an in-memory cache and a writer that counts its calls.
///
///     dart test test/export_test.dart
///
/// Mutation: look the cache up after writing instead of before and the
/// second request writes again; drop the in-flight map and two requests at
/// once write twice; serve a `.glb` source through the writer and a glTF
/// extension the engine does not read is lost; keep an export written for a
/// source that was replaced meanwhile and it is a blob nothing frees.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter3d_core/formats.dart' show GlbContainer, GlbModelWriter;
import 'package:flutter3d_models/src/convert/exporter.dart';
import 'package:flutter3d_models/src/convert/gltf_files.dart';
import 'package:flutter3d_models/src/convert/zip_guard.dart';
import 'package:flutter3d_models/src/db/models_repository.dart';
import 'package:flutter3d_models/src/storage/blob_store.dart';
import 'package:flutter3d_models/src/storage/inspect.dart';
import 'package:flutter3d_models/src/storage/model_exports.dart';
import 'package:test/test.dart';

final Uint8List _triangle = Uint8List.fromList(
  utf8.encode('v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n'),
);

/// `model_exports`, in a map.
class _MemoryCache implements ExportCache {
  final Map<String, StoredFile> rows = <String, StoredFile>{};

  /// What [keepExport] answers: false is "the source moved on".
  bool sourceIsCurrent = true;

  /// Hashes something other than an export points at.
  final Set<String> otherwiseReferenced = <String>{};

  @override
  Future<StoredFile?> exportOf({
    required String sourceSha256,
    required String format,
    required int writerVersion,
  }) async => rows.entries
      .where((e) => e.key.endsWith('/$sourceSha256/$format/$writerVersion'))
      .map((e) => e.value)
      .firstOrNull;

  @override
  Future<bool> keepExport({
    required int modelId,
    required String sourceSha256,
    required String format,
    required int writerVersion,
    required StoredFile file,
  }) async {
    if (!sourceIsCurrent) return false;
    rows['$modelId/$sourceSha256/$format/$writerVersion'] = file;
    return true;
  }

  @override
  Future<bool> isReferenced(String sha256) async =>
      otherwiseReferenced.contains(sha256) ||
      rows.values.any((file) => file.blobSha256 == sha256);
}

class _Harness {
  _Harness({ExportOutcome Function(ExportFormat format)? answer, this.gate}) {
    exports = ModelExports(
      blobs: blobs,
      cache: cache,
      run:
          (
            Uint8List source, {
            required String sourceName,
            required ExportFormat format,
            required String baseName,
          }) async {
            runs++;
            if (gate case final gate?) await gate.future;
            return answer?.call(format) ??
                Exported(
                  ExportedFile(
                    bytes: Uint8List.fromList(
                      utf8.encode('$baseName as ${format.column}'),
                    ),
                    contentType: format.contentType,
                    zipped: false,
                  ),
                );
          },
    );
  }

  final MemoryBlobStore blobs = MemoryBlobStore();
  final _MemoryCache cache = _MemoryCache();
  final Completer<void>? gate;
  late final ModelExports exports;
  int runs = 0;

  Future<StoredFile> store(Uint8List bytes, String name, String type) async =>
      StoredFile(
        blobSha256: await blobs.put(bytes),
        bytes: bytes.length,
        contentType: type,
        filename: name,
      );

  Future<ExportAnswer> ask(
    StoredFile source,
    ExportFormat format, {
    int modelId = 1,
    SourceFormat sourceFormat = SourceFormat.obj,
  }) => exports.exportOf(
    modelId: modelId,
    source: source,
    sourceFormat: sourceFormat,
    format: format,
  );
}

Future<Uint8List> _glbOfTriangle() async => const GlbModelWriter()
    .write(await decodeStoredModel(_triangle, 'tri.obj'), baseName: 'tri')
    .files
    .single
    .bytes;

void main() {
  group('the formats', () {
    test('a stored file in a format is served as itself, not rewritten', () {
      expect(ExportFormat.glb.isAlready(SourceFormat.glb), isTrue);
      expect(ExportFormat.f3d.isAlready(SourceFormat.f3d), isTrue);
      expect(ExportFormat.gltf.isAlready(SourceFormat.gltf), isTrue);
      expect(ExportFormat.stl.isAlready(SourceFormat.obj), isFalse);
      expect(ExportFormat.original.isAlready(null), isTrue);
    });

    test('the menu does not offer the original twice', () {
      final forGlb = ExportFormat.offeredFor(SourceFormat.glb);
      expect(forGlb.first, ExportFormat.original);
      expect(forGlb, isNot(contains(ExportFormat.glb)));
      expect(forGlb, contains(ExportFormat.gltf));
      // A project flattens (`toModelDocument`), so it offers everything.
      expect(
        ExportFormat.offeredFor(SourceFormat.project),
        ExportFormat.values,
      );
    });

    test('names a download after the model, and a .zip as one', () {
      expect(ExportFormat.stl.fileNameFor('chair', zipped: false), 'chair.stl');
      expect(
        ExportFormat.gltf.fileNameFor('chair', zipped: true),
        'chair-gltf.zip',
      );
      expect(exportBaseName('old oak/chair v2.GLB'), 'chair_v2');
      expect(exportBaseName('../..'), 'model');
      expect(exportBaseName(''), 'model');
    });
  });

  group('writing', () {
    // Each of these spawns an isolate and runs a real writer.
    for (final (format, type, zipped) in <(ExportFormat, String, bool)>[
      (ExportFormat.f3d, 'application/octet-stream', false),
      (ExportFormat.glb, 'model/gltf-binary', false),
      (ExportFormat.gltf, 'application/zip', true),
      (ExportFormat.stl, 'model/stl', false),
      (ExportFormat.usdz, 'model/vnd.usdz+zip', false),
    ]) {
      test('an OBJ as ${format.column}', () async {
        final outcome = await exportModel(
          _triangle,
          sourceName: 'tri.obj',
          format: format,
          baseName: 'tri',
        );
        expect(outcome, isA<Exported>());
        final file = (outcome as Exported).file;
        expect(file.contentType, type);
        expect(file.zipped, zipped);
        expect(file.bytes, isNotEmpty);
      });
    }

    test('an OBJ is one .obj, or a .zip with its .mtl beside it', () async {
      final outcome = await exportModel(
        await _glbOfTriangle(),
        sourceName: 'tri.glb',
        format: ExportFormat.obj,
        baseName: 'tri',
      );
      final file = (outcome as Exported).file;
      if (file.zipped) {
        expect(file.contentType, 'application/zip');
        final entries = unzipGuarded(file.bytes, budget: 1 << 20);
        expect(entries.keys, containsAll(['tri.obj', 'tri.mtl']));
        expect(utf8.decode(entries['tri.obj']!), contains('mtllib tri.mtl'));
      } else {
        expect(file.contentType, 'model/obj');
        expect(utf8.decode(file.bytes), contains('f '));
      }
    });

    test('a file that does not read is refused with the reader\'s reason', () {
      expect(
        exportModel(
          Uint8List.fromList(utf8.encode('dear diary')),
          sourceName: 'diary.glb',
          format: ExportFormat.stl,
          baseName: 'diary',
        ),
        completion(isA<ExportRefused>()),
      );
    });

    test('is stopped at its deadline, and says so', () async {
      final outcome = await exportModel(
        _triangle,
        sourceName: 'tri.obj',
        format: ExportFormat.glb,
        baseName: 'tri',
        deadline: Duration.zero,
      );
      expect(outcome, isA<ExportRefused>());
      expect((outcome as ExportRefused).because, contains('took longer'));
    });
  });

  group('a .gltf from a .glb', () {
    test('is a .gltf naming its .bin, with the same document', () async {
      final glb = await _glbOfTriangle();
      final files = splitGlb(glb, baseName: 'tri');
      expect(files.map((f) => f.$1), ['tri.gltf', 'tri.bin']);
      final json = jsonDecode(utf8.decode(files.first.$2)) as Map;
      final buffers = json['buffers'] as List;
      expect((buffers.single as Map)['uri'], 'tri.bin');
      expect((buffers.single as Map)['byteLength'], files[1].$2.length);
      // The binary chunk itself, unchanged when there is no image to move.
      expect(files[1].$2, GlbContainer.parse(glb).binaryChunk);
    });

    test('moves each image out to a file, and out of the .bin', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);
      final vertices = Uint8List(36);
      final binary = Uint8List.fromList([...vertices, ...png]);
      final glb = GlbContainer.encode({
        'asset': {'version': '2.0'},
        'buffers': [
          {'byteLength': binary.length},
        ],
        'bufferViews': [
          {'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
          {'buffer': 0, 'byteOffset': 36, 'byteLength': png.length},
        ],
        'accessors': [
          {'bufferView': 0, 'componentType': 5126, 'count': 3, 'type': 'VEC3'},
        ],
        'images': [
          {'bufferView': 1, 'mimeType': 'image/png'},
        ],
      }, binary: binary);
      final files = splitGlb(glb, baseName: 'crate');
      expect(files.map((f) => f.$1), [
        'crate.gltf',
        'crate.bin',
        'textures/0.png',
      ]);
      expect(files[2].$2, png);
      expect(files[1].$2, vertices, reason: 'the image is not shipped twice');
      final json = jsonDecode(utf8.decode(files.first.$2)) as Map;
      final image = (json['images'] as List).single as Map;
      expect(image['uri'], 'textures/0.png');
      expect(image.containsKey('bufferView'), isFalse);
      expect(json['bufferViews'] as List, hasLength(1));
    });

    test('goes into a .zip a reader can open', () async {
      final outcome = await exportModel(
        _triangle,
        sourceName: 'tri.obj',
        format: ExportFormat.gltf,
        baseName: 'tri',
      );
      final file = (outcome as Exported).file;
      final entries = unzipGuarded(file.bytes, budget: 1 << 20);
      expect(entries.keys, containsAll(['tri.gltf', 'tri.bin']));
    });
  });

  group('the cache', () {
    test('writes once, and the second request is a read', () async {
      final h = _Harness();
      final source = await h.store(_triangle, 'chair.obj', 'model/obj');
      final first = await h.ask(source, ExportFormat.stl);
      final second = await h.ask(source, ExportFormat.stl);
      expect(h.runs, 1);
      expect(first, isA<ExportReady>());
      expect(
        (second as ExportReady).file.blobSha256,
        (first as ExportReady).file.blobSha256,
      );
      expect(second.file.filename, 'chair.stl');
      expect(second.file.contentType, 'model/stl');
      expect(await h.blobs.sizeOf(second.file.blobSha256), isNotNull);
    });

    test('a hit written for another model is recorded for this one', () async {
      final h = _Harness();
      final source = await h.store(_triangle, 'chair.obj', 'model/obj');
      await h.ask(source, ExportFormat.glb, modelId: 1);
      await h.ask(source, ExportFormat.glb, modelId: 2);
      expect(h.runs, 1);
      expect(h.cache.rows.keys, hasLength(2));
    });

    test('two requests at once share one write', () async {
      final gate = Completer<void>();
      final h = _Harness(gate: gate);
      final source = await h.store(_triangle, 'chair.obj', 'model/obj');
      final both = Future.wait([
        h.ask(source, ExportFormat.usdz),
        h.ask(source, ExportFormat.usdz),
      ]);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      final answers = await both;
      expect(h.runs, 1);
      expect(answers, everyElement(isA<ExportReady>()));
    });

    test('a different format, or another source, is another write', () async {
      final h = _Harness();
      final chair = await h.store(_triangle, 'chair.obj', 'model/obj');
      final quad = await h.store(
        Uint8List.fromList(utf8.encode('v 0 0 0\nv 1 0 0\nv 1 1 0\nf 1 2 3\n')),
        'quad.obj',
        'model/obj',
      );
      await h.ask(chair, ExportFormat.stl);
      await h.ask(chair, ExportFormat.glb);
      await h.ask(quad, ExportFormat.stl);
      expect(h.runs, 3);
    });

    test('a stored .glb asked for as .glb is the stored file', () async {
      final h = _Harness();
      final glb = await _glbOfTriangle();
      final source = await h.store(glb, 'tri.glb', 'model/gltf-binary');
      final answer = await h.ask(
        source,
        ExportFormat.glb,
        sourceFormat: SourceFormat.glb,
      );
      expect(h.runs, 0);
      expect((answer as ExportReady).file.blobSha256, source.blobSha256);
      expect(answer.file.filename, 'tri.glb');
      expect(h.cache.rows, isEmpty);
    });

    test('a refusal is the writer\'s sentence, and is not kept', () async {
      final h = _Harness(
        answer: (_) => const ExportRefused('no surfaces to write'),
      );
      final source = await h.store(_triangle, 'chair.obj', 'model/obj');
      final first = await h.ask(source, ExportFormat.usdz);
      expect((first as ExportFailed).because, 'no surfaces to write');
      await h.ask(source, ExportFormat.usdz);
      expect(h.runs, 2, reason: 'a refusal is asked again, not remembered');
      expect(h.cache.rows, isEmpty);
    });

    test(
      'an export of a source replaced meanwhile is sent, not kept',
      () async {
        final h = _Harness()..cache.sourceIsCurrent = false;
        final source = await h.store(_triangle, 'chair.obj', 'model/obj');
        final answer = await h.ask(source, ExportFormat.stl);
        expect(answer, isA<ExportReady>());
        final ready = answer as ExportReady;
        expect(ready.inline, isNotNull);
        expect(ready.file.blobSha256, sha256.convert(ready.inline!).toString());
        expect(await h.blobs.sizeOf(ready.file.blobSha256), isNull);
        expect(h.cache.rows, isEmpty);
      },
    );

    test('a missing stored file is said, not written', () async {
      final h = _Harness();
      const source = StoredFile(
        blobSha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
        bytes: 3,
        contentType: 'model/obj',
        filename: 'ghost.obj',
      );
      final answer = await h.ask(source, ExportFormat.stl);
      expect(answer, isA<ExportFailed>());
      expect(h.runs, 0);
    });
  });

  group('in flight', () {
    test('forgets a key when its work ends, so the next one runs', () async {
      final runs = ExportRuns<int>();
      var calls = 0;
      Future<int> work() async => ++calls;
      expect(await runs.once('k', work), 1);
      expect(runs.length, 0);
      expect(await runs.once('k', work), 2);
    });
  });
}
