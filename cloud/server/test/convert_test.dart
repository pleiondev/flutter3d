/// `/convert`'s guards on the process: the archive reader that counts what
/// it inflates, the confinement that keeps the converters inside the upload,
/// the isolate that is killed at its deadline — and one real conversion
/// through `flutter3d_build`, so the adapter is known to reach it.
///
///     dart test test/convert_test.dart
///
/// Mutation: trust the sizes a ZIP states and the bomb below unpacks; join an
/// entry's name onto the directory unchecked and `../` writes outside it;
/// let a path through the confinement lexically un-normalised and
/// `in/../../etc/passwd` reads the server's files; wait on the isolate
/// without killing it and the deadline test hangs to the end of the
/// conversion instead of answering.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart' show GlbModelWriter;
import 'package:flutter3d_models/src/convert/confinement.dart';
import 'package:flutter3d_models/src/convert/converter.dart';
import 'package:flutter3d_models/src/convert/gltf_files.dart';
import 'package:flutter3d_models/src/convert/zip_guard.dart';
import 'package:flutter3d_models/src/convert/zip_writer.dart';
import 'package:flutter3d_models/src/storage/inspect.dart';
import 'package:test/test.dart';

/// One triangle, as the smallest OBJ the converter makes a model of.
final Uint8List _triangle = Uint8List.fromList(
  utf8.encode('v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n'),
);

/// A ZIP whose entries are deflated — `storedZip` writes stored ones, and
/// a bomb is only a bomb when it is compressed.
Uint8List _deflatedZip(Map<String, Uint8List> files) {
  final body = BytesBuilder();
  final directory = BytesBuilder();
  Uint8List u16(int v) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
  Uint8List u32(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
  for (final MapEntry(:key, :value) in files.entries) {
    final name = utf8.encode(key);
    final packed = Uint8List.fromList(ZLibEncoder(raw: true).convert(value));
    final offset = body.length;
    body
      ..add(u32(0x04034b50))
      ..add(u16(20))
      ..add(u16(0x800))
      ..add(u16(8))
      ..add(u16(0))
      ..add(u16(0x21))
      ..add(u32(crc32(value)))
      ..add(u32(packed.length))
      ..add(u32(value.length))
      ..add(u16(name.length))
      ..add(u16(0))
      ..add(name)
      ..add(packed);
    directory
      ..add(u32(0x02014b50))
      ..add(u16(20))
      ..add(u16(20))
      ..add(u16(0x800))
      ..add(u16(8))
      ..add(u16(0))
      ..add(u16(0x21))
      ..add(u32(crc32(value)))
      ..add(u32(packed.length))
      // What a bomb does: says it is small.
      ..add(u32(1))
      ..add(u16(name.length))
      ..add(u16(0))
      ..add(u16(0))
      ..add(u16(0))
      ..add(u16(0))
      ..add(u32(0))
      ..add(u32(offset))
      ..add(name);
  }
  final at = body.length;
  final dir = directory.takeBytes();
  body
    ..add(dir)
    ..add(u32(0x06054b50))
    ..add(u16(0))
    ..add(u16(0))
    ..add(u16(files.length))
    ..add(u16(files.length))
    ..add(u32(dir.length))
    ..add(u32(at))
    ..add(u16(0));
  return body.takeBytes();
}

void main() {
  group('the archive reader', () {
    test('reads back what the stored writer wrote', () {
      final zip = storedZip([
        ('chair.f3d', Uint8List.fromList([1, 2, 3])),
        ('materials/oak.fmat', Uint8List.fromList(utf8.encode('{}'))),
      ]);
      final entries = unzipGuarded(zip, budget: 1024);
      expect(entries.keys, ['chair.f3d', 'materials/oak.fmat']);
      expect(entries['chair.f3d'], [1, 2, 3]);
    });

    test('inflates a deflated entry', () {
      final zip = _deflatedZip({'a/scene.usda': _triangle});
      expect(unzipGuarded(zip, budget: 1024)['a/scene.usda'], _triangle);
    });

    test('stops a bomb at the budget, whatever its header says', () {
      // Sixteen megabytes of zeros, a few kilobytes deflated, and a central
      // directory that claims one byte.
      final bomb = _deflatedZip({'zeros.bin': Uint8List(16 * 1024 * 1024)});
      expect(bomb.length, lessThan(64 * 1024));
      expect(
        () => unzipGuarded(bomb, budget: 1024 * 1024),
        throwsA(
          isA<ZipRefused>().having(
            (e) => e.message,
            'message',
            contains('unpacks to more'),
          ),
        ),
      );
      expect(
        () => measureZip(bomb, budget: 1024 * 1024),
        throwsA(isA<ZipRefused>()),
      );
    });

    test('counts every entry against one budget', () {
      final zip = _deflatedZip({
        'one.bin': Uint8List(600 * 1024),
        'two.bin': Uint8List(600 * 1024),
      });
      expect(
        () => unzipGuarded(zip, budget: 1024 * 1024),
        throwsA(isA<ZipRefused>()),
      );
    });

    test('refuses an entry named outside the archive', () {
      for (final name in ['../evil.txt', 'a/../../evil.txt', '/etc/x']) {
        final zip = storedZip([(name, Uint8List(1))]);
        expect(
          () => unzipGuarded(zip, budget: 1024),
          throwsA(isA<ZipRefused>()),
          reason: name,
        );
      }
    });

    test('skips directories and macOS resource forks', () {
      final zip = storedZip([
        ('__MACOSX/._scene.usda', Uint8List(1)),
        ('scene/.DS_Store', Uint8List(1)),
        ('scene/scene.usda', _triangle),
      ]);
      expect(unzipGuarded(zip, budget: 1024).keys, ['scene/scene.usda']);
    });

    test('says plainly when it is not an archive', () {
      expect(
        () => unzipGuarded(_triangle, budget: 1024),
        throwsA(isA<ZipRefused>()),
      );
    });
  });

  group('the confinement', () {
    final confined = ConfinedFiles('/srv/work/abc');

    test('lets through what is inside the upload', () {
      expect(
        confined.confine('/srv/work/abc/in/scene.usda'),
        '/srv/work/abc/in/scene.usda',
      );
    });

    test('answers anything outside as a file that does not exist', () {
      for (final path in [
        '/etc/passwd',
        '/srv/work/abc/in/../../../etc/passwd',
        '/srv/work/abcdef/in/x',
        '/var/lib/flutter3d-models/blobs/ab/cd/abcd',
      ]) {
        final answer = confined.confine(path);
        expect(
          answer,
          startsWith('/srv/work/abc/.outside-the-upload/'),
          reason: path,
        );
      }
    });

    test('keeps a real read outside the upload from happening', () async {
      final root = Directory.systemTemp.createTempSync('confined-');
      addTearDown(() => root.deleteSync(recursive: true));
      final outside = Directory.systemTemp.createTempSync('outside-');
      addTearDown(() => outside.deleteSync(recursive: true));
      final secret = File('${outside.path}/secret.txt')
        ..writeAsStringSync('nobody else');
      final seen = await confinedTo(
        root.absolute.path,
        () async => File(secret.path).existsSync(),
      );
      expect(seen, isFalse);
    });
  });

  group('a conversion', () {
    test('turns an OBJ into a model through flutter3d_build', () async {
      final outcome = await convertUpload(
        _triangle,
        fileName: 'triangle.obj',
        target: ConversionTarget.model,
      );
      expect(outcome, isA<ConversionDone>());
      final done = outcome as ConversionDone;
      expect(done.files.map((f) => f.path), ['triangle.f3d']);
      expect(done.files.single.isModel, isTrue);
      expect(done.reports.single.converted, isTrue);
      // The server's own directory is taken out of what is shown.
      for (final line in done.reports.single.mapped) {
        expect(line, isNot(contains('flutter3d-convert-')));
      }
    });

    test(
      'a model is one bundled .f3d per input, with nothing left over',
      () async {
        // Mutation: convert a model in the sidecar layout. Its `.fmat` files
        // and textures then come back as outputs a model does not offer.
        final outcome = await convertUpload(
          _triangle,
          fileName: 'triangle.obj',
          target: ConversionTarget.model,
        );
        final done = outcome as ConversionDone;
        expect(done.files.map((f) => f.path), ['triangle.f3d']);
        expect(done.notOffered, isEmpty);
        expect(done.reports.single.written, ['triangle.f3d']);
      },
    );

    test('only a model asks for the bundle', () {
      // Mutation: bundle a material or a level. `convertFiles` then carries
      // the `.fmat`, `.f3dmat` and `.level.json` inside the `.f3d`, and
      // those targets have nothing to offer.
      expect(ConversionTarget.values.where((t) => t.bundles), [
        ConversionTarget.model,
      ]);
    });

    test(
      'a level keeps the files a conversion lays out beside the model',
      () async {
        final outcome = await convertUpload(
          _triangle,
          fileName: 'triangle.obj',
          target: ConversionTarget.level,
        );
        final done = outcome as ConversionDone;
        // Everything is a level's, so nothing is left unoffered, and the model
        // is there as a file of its own.
        expect(done.notOffered, isEmpty);
        expect(done.files.map((f) => f.path), contains('triangle.f3d'));
      },
    );

    test('offers only what the target asks for, and says what else '
        'came out', () async {
      final outcome = await convertUpload(
        _triangle,
        fileName: 'triangle.obj',
        target: ConversionTarget.material,
      );
      final done = outcome as ConversionDone;
      expect(done.files.where((f) => f.isModel), isEmpty);
      expect(done.notOffered, contains('triangle.f3d'));
    });

    test(
      'reports an FBX as needing a program this server does not run',
      () async {
        final outcome = await convertUpload(
          Uint8List.fromList(utf8.encode('Kaydara FBX Binary  \u0000')),
          fileName: 'robot.fbx',
          target: ConversionTarget.model,
        );
        final done = outcome as ConversionDone;
        expect(done.files, isEmpty);
        expect(done.reports.single.neededExternalTool, isTrue);
      },
    );

    test('refuses an archive past its budget before converting', () async {
      final outcome = await convertUpload(
        _deflatedZip({'zeros.obj': Uint8List(8 * 1024 * 1024)}),
        fileName: 'bundle.zip',
        target: ConversionTarget.level,
        expansionBudget: 1024 * 1024,
      );
      expect(
        outcome,
        isA<ConversionRefused>().having(
          (r) => r.because,
          'because',
          contains('unpacks to more'),
        ),
      );
    });

    test('is stopped at its deadline, and says so', () async {
      final outcome = await convertUpload(
        _triangle,
        fileName: 'triangle.obj',
        target: ConversionTarget.model,
        deadline: Duration.zero,
      );
      expect(
        outcome,
        isA<ConversionRefused>().having(
          (r) => r.because,
          'because',
          contains('took longer'),
        ),
      );
    });

    test('refuses an empty file without starting', () async {
      final outcome = await convertUpload(
        Uint8List(0),
        fileName: 'nothing.obj',
        target: ConversionTarget.model,
      );
      expect(outcome, isA<ConversionRefused>());
    });
  });

  group('the original "Save to my models" keeps', () {
    Future<Uint8List> glbOfTriangle() async => const GlbModelWriter()
        .write(await decodeStoredModel(_triangle, 'tri.obj'), baseName: 'tri')
        .files
        .single
        .bytes;

    test('is a .glb as it was sent', () async {
      final glb = await glbOfTriangle();
      final done =
          await convertUpload(
                glb,
                fileName: 'tri.glb',
                target: ConversionTarget.model,
              )
              as ConversionDone;
      expect(done.files.where((f) => f.isModel), hasLength(1));
      final original = done.original!;
      expect(original.asUploaded, isTrue);
      expect(original.fileName, 'tri.glb');
      expect(original.bytes, glb);
    });

    test('is an OBJ with nothing beside it as it was sent', () async {
      final done =
          await convertUpload(
                _triangle,
                fileName: 'triangle.obj',
                target: ConversionTarget.model,
              )
              as ConversionDone;
      expect(done.original?.fileName, 'triangle.obj');
      expect(done.original?.bytes, _triangle);
    });

    test('is a GLB written from a .gltf that names its .bin', () async {
      final glb = await glbOfTriangle();
      final zip = storedZip([
        for (final (path, bytes) in splitGlb(glb, baseName: 'tri'))
          ('scene/$path', bytes),
      ]);
      final done =
          await convertUpload(
                zip,
                fileName: 'scene.zip',
                target: ConversionTarget.model,
              )
              as ConversionDone;
      final original = done.original!;
      expect(original.asUploaded, isFalse);
      expect(original.writtenFrom, 'scene/tri.gltf');
      expect(original.fileName, 'tri.glb');
      // A real GLB the service would store as one.
      expect(
        await inspectInPlace(original.bytes, original.fileName),
        isA<Accepted>().having((a) => a.format, 'format', SourceFormat.glb),
      );
    });

    test('is nothing for a format the service does not store', () async {
      final done =
          await convertUpload(
                Uint8List.fromList(
                  utf8.encode(
                    'ply\nformat ascii 1.0\nelement vertex 3\n'
                    'property float x\nproperty float y\nproperty float z\n'
                    'element face 1\nproperty list uchar int vertex_indices\n'
                    'end_header\n0 0 0\n1 0 0\n0 1 0\n3 0 1 2\n',
                  ),
                ),
                fileName: 'tri.ply',
                target: ConversionTarget.model,
              )
              as ConversionDone;
      expect(done.original, isNull);
    });

    test('is nothing when the target is not a model', () async {
      final done =
          await convertUpload(
                _triangle,
                fileName: 'triangle.obj',
                target: ConversionTarget.level,
              )
              as ConversionDone;
      expect(done.original, isNull);
    });
  });

  group('safeUploadName', () {
    test('keeps the name and drops any directory or control character', () {
      expect(safeUploadName('Assets/Props/Crate.prefab'), 'Crate.prefab');
      expect(safeUploadName(r'C:\x\y.usda'), 'y.usda');
      expect(safeUploadName('a"b\u0001.obj'), 'ab.obj');
      expect(safeUploadName('..'), 'upload');
      expect(safeUploadName(''), 'upload');
    });
  });
}
