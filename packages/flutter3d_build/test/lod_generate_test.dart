/// `C5`: a converted model carries the levels it was asked for, each near its
/// triangle target, each bent further than the one before it.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:test/test.dart';

/// A sphere of a few thousand triangles, as OBJ text — built here rather than
/// checked in, because the size of the fixture is what the test is about.
String sphereObj() {
  final mesh = const SphereShape(
    radius: 1,
    segments: 48,
    rings: 32,
  ).build(layout: VertexLayout.standard);
  final stride = mesh.layout.floatsPerVertex;
  final buffer = StringBuffer();
  for (var v = 0; v < mesh.vertexCount; v++) {
    buffer.writeln(
      'v ${mesh.vertices[v * stride]} ${mesh.vertices[v * stride + 1]} '
      '${mesh.vertices[v * stride + 2]}',
    );
  }
  for (var t = 0; t < mesh.indices.length; t += 3) {
    buffer.writeln(
      'f ${mesh.indices[t] + 1} ${mesh.indices[t + 1] + 1} '
      '${mesh.indices[t + 2] + 1}',
    );
  }
  return buffer.toString();
}

void main() {
  late Directory scratch;
  late String source;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('f3d_lods_');
    source = '${scratch.path}/sphere.obj';
    File(source).writeAsStringSync(sphereObj());
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  test('a converted model carries three levels within 10% of target, '
      'with error growing down the chain', () async {
    final output = '${scratch.path}/sphere.f3d';
    final out = _BufferSink();
    final err = _BufferSink();
    final code = await runConvert(
      <String>[source, '-o', output, '--lods=0.5,0.25,0.1'],
      out: out,
      err: err,
    );
    expect(code, 0, reason: err.text);

    final document = F3dDocument.parse(File(output).readAsBytesSync());
    final node = document.nodes.singleWhere((n) => n.surfaces.isNotEmpty);
    final base = document.surfaces[node.surfaces.single].mesh.triangleCount;
    expect(base, greaterThan(2000));
    expect(node.lods, hasLength(3));

    final ratios = <double>[0.5, 0.25, 0.1];
    for (var level = 0; level < 3; level++) {
      final lod = node.lods[level];
      final triangles =
          document.surfaces[lod.surfaceIndices.single].mesh.triangleCount;
      final target = base * ratios[level];
      expect(
        (triangles - target).abs() / target,
        lessThan(0.1),
        reason: 'level $level has $triangles triangles for $target',
      );
    }
    // Every level carries the distance it was measured at, through the
    // file, growing down the chain and a small fraction of the unit radius.
    final stored = <double>[for (final lod in node.lods) lod.error!];
    expect(stored[0], greaterThan(0.0));
    expect(stored[1], greaterThanOrEqualTo(stored[0]));
    expect(stored[2], greaterThanOrEqualTo(stored[1]));
    expect(stored[2], lessThan(0.1));

    // Coarser levels take over at smaller sizes on screen.
    expect(
      node.lods[0].maxScreenFraction,
      greaterThan(node.lods[1].maxScreenFraction),
    );
    expect(
      node.lods[1].maxScreenFraction,
      greaterThan(node.lods[2].maxScreenFraction),
    );

    // The error each level reached, as the converter reported it and as
    // generateLods measures it on the same decoded source.
    expect(out.text, contains('lod 0.50'));
    final reports = <LodLevelReport>[];
    generateLods(
      F3dDocument.parse(File(output).readAsBytesSync()),
      ratios,
      report: reports.add,
    );
    // The file already has levels, so the node keeps them and nothing is cut.
    expect(reports.every((r) => r.targetTriangles == 0), isTrue);

    final fresh = await decodeModelBytes(
      ModelLoadRequest(source: _Named(source), layout: VertexLayout.standard),
      File(source).readAsBytesSync(),
      fileUriResolverFor(source),
    );
    generateLods(fresh, ratios, report: reports.add);
    final errors = <double>[for (final r in reports.skip(3)) r.error];
    expect(errors[0], greaterThan(0));
    expect(errors[1], greaterThan(errors[0]));
    // The report and the file say the same thing.
    for (var level = 0; level < 3; level++) {
      expect(stored[level], closeTo(errors[level], errors[level] * 1e-3));
    }
    expect(errors[2], greaterThan(errors[1]));
  });

  test('without --lods the file carries no levels', () async {
    final output = '${scratch.path}/plain.f3d';
    final code = await runConvert(<String>[
      source,
      '-o',
      output,
    ], out: _BufferSink());
    expect(code, 0);
    final document = F3dDocument.parse(File(output).readAsBytesSync());
    expect(document.nodes.every((n) => n.lods.isEmpty), isTrue);
  });

  test('a ratio outside (0, 1) is refused with the usage text', () async {
    for (final bad in <String>['--lods=1', '--lods=0,0.5', '--lods=half']) {
      final err = _BufferSink();
      final code = await runConvert(<String>[source, bad], err: err);
      expect(code, 2, reason: bad);
      expect(err.text, contains('--lods'));
    }
  });

  test('a manifest rule\'s lods reach the build, and changing them '
      'reconverts', () async {
    final project = Directory('${scratch.path}/project')..createSync();
    Directory('${project.path}/assets_src').createSync();
    File(source).copySync('${project.path}/assets_src/ball.obj');
    final manifest = File('${project.path}/flutter3d_assets.yaml')
      ..writeAsStringSync('''
rules:
  - glob: "**/*.obj"
    lods: [0.5, 0.2]
''');

    final first = await runAssetBuild(project, log: _BufferSink());
    expect(first.converted, hasLength(1));
    final built = F3dDocument.parse(
      File('${project.path}/flutter3d_generated/ball.f3d').readAsBytesSync(),
    );
    expect(
      built.nodes.singleWhere((n) => n.surfaces.isNotEmpty).lods,
      hasLength(2),
    );

    final again = await runAssetBuild(project, log: _BufferSink());
    expect(again.skipped, hasLength(1));

    manifest.writeAsStringSync('''
rules:
  - glob: "**/*.obj"
    lods: [0.5]
''');
    final changed = await runAssetBuild(project, log: _BufferSink());
    expect(changed.converted, hasLength(1));
  });

  test('a manifest lods entry that is not a ratio names its line', () {
    expect(
      () => AssetManifest.parse('''
rules:
  - glob: "*.obj"
    lods:
      - 0.5
      - 2
'''),
      throwsA(isA<ManifestFormatException>().having((e) => e.line, 'line', 5)),
    );
  });
}

final class _Named extends AssetSource {
  const _Named(this.path);

  final String path;

  @override
  String get key => 'file:$path';

  @override
  Future<Uint8List> read() => File(path).readAsBytes();

  @override
  AssetUriResolver get resolveUri => fileUriResolverFor(path);
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
