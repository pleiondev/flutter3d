import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:test/test.dart';

void main() {
  late Directory project;

  setUp(() => project = Directory.systemTemp.createTempSync('f3d_build_'));
  tearDown(() => project.deleteSync(recursive: true));

  final buffer = StringBuffer();
  final log = _StringSink(buffer);

  setUp(buffer.clear);

  void writeSource(String relative) {
    final file = File('${project.path}/assets_src/$relative')
      ..parent.createSync(recursive: true);
    file.writeAsStringSync('''
v 0.0 0.0 0.0
v 1.0 0.0 0.0
v 0.0 1.0 0.0
f 1 2 3
''');
  }

  test('an empty project converts nothing and logs zero of both', () async {
    final report = await runAssetBuild(project, log: log);

    expect(report.converted, isEmpty);
    expect(report.skipped, isEmpty);
    expect(report.dependencies, isEmpty);
    expect(log.text, contains('0 converted, 0 unchanged'));
  });

  test('a fresh source converts once', () async {
    writeSource('hero.obj');

    final report = await runAssetBuild(project, log: log);

    expect(report.converted, hasLength(1));
    expect(report.skipped, isEmpty);
    expect(
      File('${project.path}/flutter3d_generated/hero.f3d').existsSync(),
      isTrue,
    );
  });

  test('the acceptance line: a second build with nothing changed converts '
      'nothing, and the log says so as a count', () async {
    writeSource('hero.obj');
    writeSource('props/chair.obj');

    await runAssetBuild(project, log: log);
    buffer.clear();
    final second = await runAssetBuild(project, log: log);

    expect(second.converted, isEmpty);
    expect(second.skipped, hasLength(2));
    expect(log.text, contains('0 converted, 2 unchanged'));
  });

  test(
    'the acceptance line: changing one source reconverts exactly that one',
    () async {
      writeSource('hero.obj');
      writeSource('props/chair.obj');
      await runAssetBuild(project);

      // A real edit — different vertex data, not a touched mtime.
      File('${project.path}/assets_src/hero.obj').writeAsStringSync('''
v 0.0 0.0 0.0
v 2.0 0.0 0.0
v 0.0 2.0 0.0
f 1 2 3
''');

      final report = await runAssetBuild(project, log: log);

      expect(report.converted, <String>['${project.path}/assets_src/hero.obj']);
      expect(report.skipped, hasLength(1));
      expect(report.skipped.single, contains('chair.obj'));
    },
  );

  test(
    'a destination that vanished is rebuilt even if the cache agrees',
    () async {
      writeSource('hero.obj');
      await runAssetBuild(project);
      File('${project.path}/flutter3d_generated/hero.f3d').deleteSync();

      final report = await runAssetBuild(project, log: log);

      expect(report.converted, hasLength(1));
      expect(
        File('${project.path}/flutter3d_generated/hero.f3d').existsSync(),
        isTrue,
      );
    },
  );

  test('the acceptance line: a pipeline-version stamp change forces a full '
      'reconvert with the content unchanged', () async {
    writeSource('hero.obj');
    await runAssetBuild(project);

    // Simulate a later flutter3d_build release by rewriting the cache
    // file with a stamp this run will not recognise — the same effect
    // kAssetPipelineVersion moving would have, without needing two
    // built copies of this package side by side to prove it.
    final cache = File(
      '${project.path}/flutter3d_generated/.flutter3d_cache.json',
    );
    final json = jsonDecode(cache.readAsStringSync()) as Map<String, Object?>;
    for (final entry in json.values) {
      (entry! as Map<String, Object?>)['pipelineVersion'] = 0;
    }
    cache.writeAsStringSync(jsonEncode(json));

    final report = await runAssetBuild(project, log: log);

    expect(report.converted, hasLength(1));
    expect(report.skipped, isEmpty);
  });

  test('a format-version stamp change forces a full reconvert too, the same '
      'way', () async {
    writeSource('hero.obj');
    await runAssetBuild(project);

    final cache = File(
      '${project.path}/flutter3d_generated/.flutter3d_cache.json',
    );
    final json = jsonDecode(cache.readAsStringSync()) as Map<String, Object?>;
    for (final entry in json.values) {
      (entry! as Map<String, Object?>)['formatVersion'] = 0;
    }
    cache.writeAsStringSync(jsonEncode(json));

    final report = await runAssetBuild(project, log: log);

    expect(report.converted, hasLength(1));
  });

  test(
    'every planned source is a dependency, converted or skipped alike — '
    'the next build has to be asked for regardless of this one\'s cache',
    () async {
      writeSource('hero.obj');
      writeSource('props/chair.obj');
      await runAssetBuild(project);

      final report = await runAssetBuild(project);

      expect(report.dependencies, hasLength(2));
    },
  );

  test('a broken cache file is treated as empty, not fatal', () async {
    writeSource('hero.obj');
    Directory(
      '${project.path}/flutter3d_generated',
    ).createSync(recursive: true);
    File(
      '${project.path}/flutter3d_generated/.flutter3d_cache.json',
    ).writeAsStringSync('not json at all {{{');

    final report = await runAssetBuild(project, log: log);

    expect(report.converted, hasLength(1));
  });
}

final class _StringSink implements IOSink {
  _StringSink(this._buffer);
  final StringBuffer _buffer;
  String get text => _buffer.toString();

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  void add(List<int> data) => _buffer.write(utf8.decode(data));

  @override
  Encoding encoding = utf8;

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  Future<void> flush() async {}

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);
}
