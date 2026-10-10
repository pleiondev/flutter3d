/// The plugin author's MCP server: its tools, a plugin created into a
/// directory, a conformance run read from the JSON reporter, and the badge.
///
///     dart test test/plugin_author_server_test.dart
///
/// The conformance tool runs no process here: the workshop is handed a
/// runner that answers with a canned reporter stream, so what is tested is
/// how a stream is read and judged, which is the part that can be wrong.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// A JSON reporter stream: the hidden load, then one test per check, each
/// with the result given.
String _stream(Map<String, String> results) {
  final lines = <Map<String, Object?>>[
    <String, Object?>{
      'type': 'testStart',
      'test': <String, Object?>{
        'id': 1,
        'name': 'loading test/conformance_test.dart',
      },
    },
    <String, Object?>{
      'type': 'testDone',
      'testID': 1,
      'result': 'success',
      'skipped': false,
      'hidden': true,
    },
  ];
  var id = 2;
  for (final MapEntry(key: name, value: result) in results.entries) {
    lines.add(<String, Object?>{
      'type': 'testStart',
      'test': <String, Object?>{
        'id': id,
        'name': 'plugin conformance $name',
        'metadata': <String, Object?>{
          'skip': result == 'skipped',
          'skipReason': result == 'skipped' ? 'no world was given' : null,
        },
      },
    });
    if (result == 'failure') {
      lines.add(<String, Object?>{
        'type': 'error',
        'testID': id,
        'error': 'step 3: system "x.step" gave two answers\nmore',
      });
    }
    lines.add(<String, Object?>{
      'type': 'testDone',
      'testID': id,
      'result': result == 'skipped' ? 'success' : result,
      'skipped': result == 'skipped',
      'hidden': false,
    });
    id++;
  }
  return lines.map(jsonEncode).join('\n');
}

const Map<String, String> _allPass = <String, String>{
  'manifest': 'success',
  'switch': 'success',
  'determinism': 'success',
  'backends on cpu': 'success',
  'budget': 'success',
};

Directory _temp() {
  final dir = Directory.systemTemp.createTempSync('f3d_author_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// A workshop whose runner answers [stdout] with [exitCode], recording what
/// it was asked to run.
PluginWorkshop _workshop(
  String stdout, {
  int exitCode = 0,
  List<String>? ran,
}) => PluginWorkshop(
  run: (String executable, List<String> arguments, String directory) async {
    ran?.add('$executable ${arguments.join(' ')}');
    return (exitCode: exitCode, stdout: stdout, stderr: '');
  },
);

void main() {
  test('the server offers three tools, each with a schema and the '
      'arguments it requires', () async {
    // Mutation: leave `directory` out of a tool's `required`. A call with
    // no directory reaches `arguments['directory']!` and throws.
    final server = PluginAuthorMcpServer(
      StreamChannelController<String>().local,
      session: PluginWorkshop(),
    );
    addTearDown(server.shutdown);
    expect(server.tools.map((t) => t.name), <String>[
      'plugin.create',
      'plugin.conformance',
      'plugin.report',
    ]);
    for (final offered in server.tools) {
      expect(offered.spec.required, contains('directory'));
    }
    expect(server.schemaVersion, pluginAuthorMcpSchemaVersion);
  });

  test('the version it announces is the pubspec\'s', () {
    // Mutation: bump the pubspec and not the constant.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('\nversion: $pluginAuthorMcpVersion\n'));
  });

  group('plugin.create', () {
    test('writes the template into an empty directory', () {
      final dir = _temp();
      final answer = PluginWorkshop().create(
        '${dir.path}/duel',
        'duel',
        PluginKind.genre,
      );
      expect(answer.did, isTrue);
      expect(File('${dir.path}/duel/lib/duel.dart').existsSync(), isTrue);
      expect(
        File('${dir.path}/duel/test/conformance_test.dart').existsSync(),
        isTrue,
      );
    });

    test('refuses a directory that holds anything', () {
      // Mutation: drop the emptiness check. A second create over a plugin
      // somebody has been editing writes their work over.
      final dir = _temp();
      File('${dir.path}/notes.txt').writeAsStringSync('mine');
      final answer = PluginWorkshop().create(
        dir.path,
        'duel',
        PluginKind.genre,
      );
      expect(answer.did, isFalse);
      expect(answer.says, contains('not empty'));
      expect(File('${dir.path}/pubspec.yaml').existsSync(), isFalse);
    });
  });

  group('plugin.conformance', () {
    test('runs the suite with the JSON reporter and reads each test', () async {
      // Mutation: count the hidden load as a test. Every run would report
      // one more test than the suite has.
      final dir = _temp();
      PluginWorkshop().create(dir.path, 'duel', PluginKind.genre);
      final ran = <String>[];
      final workshop = _workshop(
        _stream(<String, String>{..._allPass, 'determinism': 'failure'}),
        exitCode: 1,
        ran: ran,
      );
      final answer = await workshop.conformance(dir.path);
      expect(ran, <String>[
        'dart test test/conformance_test.dart --reporter json',
      ]);
      expect(answer.did, isTrue);
      expect(answer.says, startsWith('4 of 5 passed'));
      expect(answer.says, contains('gave two answers'));
      final run = workshop.lastRun(dir.path)!;
      expect(run.tests, hasLength(5));
      expect(
        run.tests.map((ConformanceTest t) => t.check),
        pluginConformanceChecks,
      );
      expect(run.earnsBadge, isFalse);
    });

    test('refuses a directory with no conformance suite', () async {
      final answer = await _workshop('').conformance(_temp().path);
      expect(answer.did, isFalse);
      expect(answer.says, contains('test/conformance_test.dart'));
    });
  });

  group('plugin.report', () {
    test('names the marker, and the badge once every check passed', () async {
      // Mutation: give the badge when the exit code is nought. A suite
      // missing the budget check exits nought too.
      final dir = _temp();
      PluginWorkshop().create(dir.path, 'duel', PluginKind.genre);
      final workshop = _workshop(_stream(_allPass));
      expect(
        workshop.report(dir.path).says,
        contains('no conformance run yet'),
      );
      await workshop.conformance(dir.path);
      final report = workshop.report(dir.path).says;
      expect(report, contains('plugin: package:duel/duel.dart#DuelPlugin'));
      expect(report, contains('backends: passed'));
      expect(report, contains('badge: conformant@1.0'));
    });

    test('a declined check is no badge, and says so', () async {
      // Mutation: count a skipped test as passed. A plugin whose suite gave
      // determinism no world would wear a badge for a check never made.
      final dir = _temp();
      PluginWorkshop().create(dir.path, 'duel', PluginKind.genre);
      final workshop = _workshop(
        _stream(<String, String>{..._allPass, 'determinism': 'skipped'}),
      );
      await workshop.conformance(dir.path);
      final report = workshop.report(dir.path).says;
      expect(report, contains('determinism: declined'));
      expect(report, contains('badge: not earned'));
    });

    test('a check no test covered is named as not run', () async {
      // Mutation: judge the badge on the tests alone. A suite that never
      // ran the budget check would pass every test it had.
      final dir = _temp();
      PluginWorkshop().create(dir.path, 'duel', PluginKind.genre);
      final workshop = _workshop(
        _stream(Map<String, String>.of(_allPass)..remove('budget')),
      );
      await workshop.conformance(dir.path);
      final report = workshop.report(dir.path).says;
      expect(report, contains('budget: not run'));
      expect(report, contains('(not run: budget)'));
    });
  });
}
