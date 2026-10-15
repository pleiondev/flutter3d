import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_build/cli.dart';
import 'package:test/test.dart';

/// Each `--json` command prints the top-level keys `cliJsonBodies` commits
/// for it, after the envelope: every key it names that is not optional, and
/// none it does not name.
///
/// **The committed shape was a hand-written string**, and the only run of a
/// `--json` command in a test did not read its keys, so a key renamed in
/// the code and not in the string reached the snapshot as a promise the
/// command no longer kept.
void main() {
  late Directory project;
  setUp(() {
    project = Directory.systemTemp.createTempSync('cli_json');
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: game\n');
    File('${project.path}/.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"configVersion": 2, "packages": []}\n');
  });
  tearDown(() => project.deleteSync(recursive: true));

  test('the commands here are the ones the surface says take --json', () {
    expect(cliJsonBodies.keys.toSet(), <String>{
      'convert',
      'doctor',
      'plugins',
      'shaders',
    });
  });

  test('convert', () async {
    final obj = File('${project.path}/tri.obj')
      ..writeAsStringSync('v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n');
    final document = await _json(<String>[
      'convert',
      obj.path,
      '-o',
      '${project.path}/out',
      '--dry-run',
      '--json',
    ], project);
    _holds(document, 'convert');
  });

  test('doctor', () async {
    _holds(await _json(const <String>['doctor', '--json'], project), 'doctor');
  });

  test('plugins, with --check and without', () async {
    _holds(
      await _json(const <String>['plugins', '--check', '--json'], project),
      'plugins',
    );
    _holds(
      await _json(const <String>['plugins', '--json'], project),
      'plugins',
    );
  });

  test('shaders', () async {
    _holds(
      await _json(const <String>['shaders', '--json'], project),
      'shaders',
    );
  });
}

/// [document]'s keys after the envelope against `cliJsonBodies[command]`.
void _holds(Map<String, Object?> document, String command) {
  expect(document['format'], 'f3d.cli');
  expect(document['command'], command);
  final keys = document.keys.toSet()
    ..removeAll(const <String>{
      'format',
      'version',
      'requires',
      'generator',
      'command',
    });
  final declared = _topKeys(cliJsonBodies[command]!);
  // Mutation: rename `dryRun` in convert's body and not in
  // `cliJsonBodies`, or the other way round, and this names it.
  expect(
    keys.difference(declared.keys.toSet()),
    isEmpty,
    reason: 'printed and not in cliJsonBodies',
  );
  expect(
    <String>{
      for (final MapEntry(:key, :value) in declared.entries)
        if (!value) key,
    }.difference(keys),
    isEmpty,
    reason: 'in cliJsonBodies and not printed',
  );
}

/// The top-level keys of a `cliJsonBodies` shape, each with whether it is
/// optional (`error?`): `{a, b?, c: [{d}]}` is a, b and c.
Map<String, bool> _topKeys(String shape) {
  final inner = shape
      .trim()
      .substring(1, shape.trim().length - 1)
      .replaceAll(RegExp(r'\([^)]*\)'), '');
  final keys = <String, bool>{};
  var depth = 0;
  final word = StringBuffer();
  void take() {
    final text = word.toString().trim();
    word.clear();
    if (text.isEmpty) return;
    final name = text.split(':').first.trim();
    keys[name.replaceAll('?', '')] = name.endsWith('?');
  }

  for (final char in inner.split('')) {
    if (char == '{' || char == '[') depth++;
    if (char == '}' || char == ']') depth--;
    if (char == ',' && depth == 0) {
      take();
    } else if (depth == 0 || char == ':') {
      word.write(char);
    }
  }
  take();
  return keys;
}

/// The document `flutter3d` prints for [arguments], run in [directory].
Future<Map<String, Object?>> _json(
  List<String> arguments,
  Directory directory,
) async {
  final out = _Caught();
  final err = _Caught();
  await IOOverrides.runZoned(
    () => runFlutter3d(arguments),
    stdout: () => out,
    stderr: () => err,
    getCurrentDirectory: () => directory,
  );
  final text = '${out.text}';
  final start = text.indexOf('{');
  expect(start, isNonNegative, reason: 'no JSON in:\n$text\n${err.text}');
  return jsonDecode(text.substring(start)) as Map<String, Object?>;
}

/// A stream that keeps what is written to it.
final class _Caught implements Stdout {
  final StringBuffer text = StringBuffer();

  @override
  void write(Object? object) => text.write(object);

  @override
  void writeln([Object? object = '']) => text.writeln(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      text.writeAll(objects, separator);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
