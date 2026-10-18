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
  'plugin.manifest': 'success',
  'plugin.switch': 'success',
  'plugin.names': 'success',
  'plugin.determinism': 'success',
  'plugin.backends on cpu': 'success',
  'plugin.budget': 'success',
  'plugin.materials': 'success',
};

Directory _temp() {
  final dir = Directory.systemTemp.createTempSync('f3d_author_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// A workshop whose runner answers [stdout] with [exitCode], recording what
/// it was asked to run, and writes [report] as the suite's
/// `duel.conformance.json` the way `runPluginConformance` does.
PluginWorkshop _workshop(
  String stdout, {
  int exitCode = 0,
  List<String>? ran,
  Map<String, Object?>? report,
}) => PluginWorkshop(
  run: (String executable, List<String> arguments, String directory) async {
    ran?.add('$executable ${arguments.join(' ')}');
    if (report != null) {
      File(
        '$directory/duel.conformance.json',
      ).writeAsStringSync(jsonEncode(report));
    }
    return PluginProcessResult(exitCode: exitCode, stdout: stdout, stderr: '');
  },
);

/// An `f3d.conformance` report as the suite writes it: one outcome a check
/// in [results] (`passed`, `declined` or `failed`), and the [badge] the
/// suite's judge gave.
Map<String, Object?> _report(Map<String, String> results, {String? badge}) =>
    <String, Object?>{
      'format': 'f3d.conformance',
      'version': 1,
      'requires': const <String>[],
      'generator': 'flutter3d_conformance',
      'plugin': 'duel',
      'suite': '1.0',
      'badge': badge,
      'outcomes': <Object?>[
        for (final MapEntry(key: check, value: result) in results.entries)
          <String, Object?>{
            'check': check,
            'passed': result == 'passed',
            'declined': result == 'declined',
            'says': result == 'failed' ? 'gave two answers' : 'fine',
          },
      ],
    };

const Map<String, String> _allPassed = <String, String>{
  'plugin.manifest': 'passed',
  'plugin.switch': 'passed',
  'plugin.names': 'passed',
  'plugin.determinism': 'passed',
  'plugin.backends': 'passed',
  'plugin.budget': 'passed',
  'plugin.materials': 'passed',
};

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
        _stream(<String, String>{..._allPass, 'plugin.determinism': 'failure'}),
        exitCode: 1,
        ran: ran,
      );
      final answer = await workshop.conformance(dir.path);
      expect(ran, <String>[
        'dart test test/conformance_test.dart --reporter json',
      ]);
      expect(answer.did, isTrue);
      expect(answer.says, startsWith('6 of 7 passed'));
      expect(answer.says, contains('gave two answers'));
      final run = workshop.lastRun(dir.path)!;
      expect(run.tests, hasLength(7));
      expect(run.report, isNull);
      expect(run.badge, isNull);
      expect(answer.says, contains('wrote no duel.conformance.json'));
    });

    test('a report left by an earlier run is not read as this one', () async {
      // Mutation: keep the old file. A suite that no longer compiles would
      // be told it earns the badge its last good run earned.
      final dir = _temp();
      PluginWorkshop().create(dir.path, 'duel', PluginKind.genre);
      File('${dir.path}/duel.conformance.json').writeAsStringSync(
        jsonEncode(_report(_allPassed, badge: 'conformant@1.0')),
      );
      final workshop = _workshop(_stream(_allPass), exitCode: 1);
      await workshop.conformance(dir.path);
      expect(workshop.lastRun(dir.path)!.badge, isNull);
      expect(File('${dir.path}/duel.conformance.json').existsSync(), isFalse);
    });

    test('refuses a directory with no conformance suite', () async {
      final answer = await _workshop('').conformance(_temp().path);
      expect(answer.did, isFalse);
      expect(answer.says, contains('test/conformance_test.dart'));
    });
  });

  group('plugin.report', () {
    test('names the marker, and the badge the suite\'s report gives', () async {
      final dir = _temp();
      PluginWorkshop().create(dir.path, 'duel', PluginKind.genre);
      final workshop = _workshop(
        _stream(_allPass),
        report: _report(_allPassed, badge: 'conformant@1.0'),
      );
      expect(
        workshop.report(dir.path).says,
        contains('no conformance report yet (duel.conformance.json'),
      );
      final ran = await workshop.conformance(dir.path);
      expect(ran.says, contains('earns the badge conformant@1.0'));
      final report = workshop.report(dir.path).says;
      expect(report, contains('plugin: package:duel/duel.dart#DuelPlugin'));
      expect(report, contains('plugin.backends: passed'));
      expect(report, contains('badge: conformant@1.0'));
    });

    test('the badge is the report\'s, whatever the tests say', () async {
      // Mutation: judge the badge here again, from the tests that passed.
      // Every test passed and the suite's judge gave none (a check its
      // suite version counts was not run), so there is none.
      final dir = _temp();
      PluginWorkshop().create(dir.path, 'duel', PluginKind.genre);
      final workshop = _workshop(
        _stream(_allPass),
        report: _report(
          Map<String, String>.of(_allPassed)..remove('plugin.names'),
        ),
      );
      await workshop.conformance(dir.path);
      final report = workshop.report(dir.path).says;
      expect(report, contains('badge: not earned'));
      expect(report, isNot(contains('plugin.names:')));
    });

    test('a declined or failed check is said as the report says it', () async {
      final dir = _temp();
      PluginWorkshop().create(dir.path, 'duel', PluginKind.genre);
      final workshop = _workshop(
        _stream(_allPass),
        report: _report(<String, String>{
          ..._allPassed,
          'plugin.determinism': 'declined',
          'plugin.budget': 'failed',
        }),
      );
      await workshop.conformance(dir.path);
      final report = workshop.report(dir.path).says;
      expect(report, contains('plugin.determinism: declined'));
      expect(report, contains('plugin.budget: failed — gave two answers'));
      expect(report, contains('badge: not earned'));
    });

    test('the report is read from the disk, whoever ran the suite', () {
      // A suite run from a terminal, not through this server, still says.
      final dir = _temp();
      PluginWorkshop().create(dir.path, 'duel', PluginKind.genre);
      File('${dir.path}/duel.conformance.json').writeAsStringSync(
        jsonEncode(_report(_allPassed, badge: 'conformant@1.0')),
      );
      expect(
        PluginWorkshop().report(dir.path).says,
        contains('badge: conformant@1.0'),
      );
    });

    test('a report newer than this build reads is refused, saying so', () {
      final dir = _temp();
      PluginWorkshop().create(dir.path, 'duel', PluginKind.genre);
      File('${dir.path}/duel.conformance.json').writeAsStringSync(
        jsonEncode(<String, Object?>{..._report(_allPassed), 'version': 2}),
      );
      final answer = PluginWorkshop().report(dir.path);
      expect(answer.did, isFalse);
      expect(answer.says, contains('update flutter3d_build'));
    });
  });
}
