/// `C9`: `convert --chunks` and a manifest rule's `chunks:` split the big
/// static meshes of a converted model, and nothing else.
library;

import 'dart:io';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:test/test.dart';

import 'lod_generate_test.dart' show sphereObj;

void main() {
  late Directory scratch;
  late String source;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('f3d_chunks_');
    source = '${scratch.path}/sphere.obj';
    File(source).writeAsStringSync(sphereObj());
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  MeshData convertedMesh(String output) =>
      F3dDocument.parse(File(output).readAsBytesSync()).surfaces.single.mesh;

  test('--chunks splits a mesh above the threshold into clusters', () async {
    final output = '${scratch.path}/split.f3d';
    final out = _BufferSink();
    final err = _BufferSink();
    final code = await runConvert(
      <String>[source, '-o', output, '--chunks=1000'],
      out: out,
      err: err,
    );
    expect(code, 0, reason: err.text);
    final mesh = convertedMesh(output);
    final table = mesh.clusters!;
    expect(mesh.triangleCount, greaterThan(1000));
    expect(table.length, greaterThan(1));
    expect(table.indexCount, mesh.indexCount);
    expect(out.text, contains('chunks: 1 meshes above 1000'));
  });

  test(
    'a mesh at or below the threshold, or no --chunks, stays whole',
    () async {
      final below = '${scratch.path}/below.f3d';
      final plain = '${scratch.path}/plain.f3d';
      expect(
        await runConvert(<String>[
          source,
          '-o',
          below,
          '--chunks=100000',
        ], out: _BufferSink()),
        0,
      );
      expect(
        await runConvert(<String>[source, '-o', plain], out: _BufferSink()),
        0,
      );
      expect(convertedMesh(below).clusters, isNull);
      expect(convertedMesh(plain).clusters, isNull);
    },
  );

  test('a threshold that is not a positive count is refused', () async {
    for (final bad in <String>['--chunks=0', '--chunks=many']) {
      final err = _BufferSink();
      expect(await runConvert(<String>[source, bad], err: err), 2);
      expect(err.text, contains('--chunks'));
    }
  });

  test('a skinned or morphing mesh is left whole', () {
    final sphere = const SphereShape(segments: 48, rings: 32).build();
    final document = PlainModelDocument(
      surfaces: <ModelSurface>[
        ModelSurface(mesh: sphere),
        ModelSurface(mesh: sphere, skinIndex: 0),
      ],
    );
    final (split, count) = splitLargeMeshes(document, threshold: 100);
    expect(count, 0);
    expect(split.surfaces.every((s) => s.mesh.clusters == null), isTrue);
  });

  test('a manifest rule\'s chunks reach the build, and adding it '
      'reconverts', () async {
    final project = Directory('${scratch.path}/project')..createSync();
    Directory('${project.path}/assets_src').createSync();
    File(source).copySync('${project.path}/assets_src/ball.obj');
    final manifest = File('${project.path}/flutter3d_assets.yaml')
      ..writeAsStringSync('''
rules:
  - glob: "**/*.obj"
''');
    final built = '${project.path}/flutter3d_generated/ball.f3d';

    await runAssetBuild(project, log: _BufferSink());
    expect(convertedMesh(built).clusters, isNull);

    manifest.writeAsStringSync('''
rules:
  - glob: "**/*.obj"
    chunks: 1000
''');
    final changed = await runAssetBuild(project, log: _BufferSink());
    expect(changed.converted, hasLength(1));
    expect(convertedMesh(built).clusters, isNotNull);
  });

  test('a manifest chunks entry takes true or a count', () {
    AssetRule rule(String value) => AssetManifest.parse('''
rules:
  - glob: "*.obj"
    chunks: $value
''').rules.single;
    expect(rule('true').chunks, kDefaultChunkThreshold);
    expect(rule('false').chunks, isNull);
    expect(rule('200000').chunks, 200000);
    expect(
      () => rule('-3'),
      throwsA(isA<ManifestFormatException>().having((e) => e.line, 'line', 3)),
    );
  });
}

final class _BufferSink implements IOSink {
  final StringBuffer _buffer = StringBuffer();

  String get text => _buffer.toString();

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
