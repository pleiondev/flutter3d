/// `convertOne` and a directory walk, through an application's own decoder
/// rather than a list of suffixes this package keeps.
///
///     dart test test/convert_decoders_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A `.tri` file, whatever its bytes: one triangle.
final class _Tri implements ModelDecoder {
  const _Tri();

  @override
  bool handles(String fileName, Uint8List bytes) =>
      fileName.toLowerCase().endsWith('.tri');

  @override
  Future<ModelDocument> decode(
    Uint8List bytes,
    ModelLoadRequest request,
    AssetUriResolver resolveUri,
  ) async {
    final builder = MeshBuilder(
      VertexLayout.standard,
      reserveVertices: 3,
      reserveIndices: 3,
    );
    for (var i = 0; i < 3; i++) {
      builder.addVertex(
        position: Vector3(i.toDouble(), 0.0, 0.0),
        normal: Vector3(0.0, 0.0, 1.0),
        texcoord: Vector2(0.0, 0.0),
        tangent: Vector4(1.0, 0.0, 0.0, 1.0),
        color: Vector4(1.0, 1.0, 1.0, 1.0),
      );
    }
    builder.addTriangle(0, 1, 2);
    return PlainModelDocument(
      surfaces: <ModelSurface>[
        ModelSurface(
          name: 'tri',
          mesh: builder.build(),
          transform: Matrix4.identity(),
        ),
      ],
    );
  }
}

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('flutter3d_build_decoders');
  });

  tearDown(() => workspace.deleteSync(recursive: true));

  Future<(bool, String)> convert(List<ModelDecoder> decoders) async {
    final source = File('${workspace.path}/part.tri')
      ..writeAsBytesSync(<int>[0]);
    final logFile = File('${workspace.path}/log.txt');
    final log = logFile.openWrite();
    final ok = await convertOne(
      source.path,
      '${workspace.path}/part.f3d',
      log,
      log,
      decoders: decoders,
    );
    await log.close();
    return (ok, logFile.readAsStringSync());
  }

  test(
    'a file only an application decoder reads converts through it',
    () async {
      // Mutation: go back to `_decode`'s own suffix `switch`. The decoder an
      // application built is never asked, and the file is "unrecognised".
      final (bool ok, String log) = await convert(const <ModelDecoder>[_Tri()]);
      expect(ok, isTrue, reason: log);
      final converted = F3dDocument.parse(
        File('${workspace.path}/part.f3d').readAsBytesSync(),
      );
      expect(converted.surfaces, hasLength(1));
    },
  );

  test(
    'without that decoder it is an unrecognised extension, as it was',
    () async {
      final (bool ok, String log) = await convert(const <ModelDecoder>[]);
      expect(ok, isFalse);
      expect(log, contains('Unrecognised extension'));
    },
  );

  test(
    'a directory walk picks the file up by the name the decoder claims',
    () async {
      File('${workspace.path}/part.tri').writeAsBytesSync(<int>[0]);
      final logFile = File('${workspace.path}/log.txt');
      final log = logFile.openWrite();
      final code = await runConvert(
        <String>[workspace.path],
        out: log,
        err: log,
        decoders: const <ModelDecoder>[_Tri()],
      );
      await log.close();
      expect(code, 0, reason: logFile.readAsStringSync());
      expect(File('${workspace.path}/part.f3d').existsSync(), isTrue);
    },
  );
}
