/// An MCP server for the author of a plugin: create one from a template, run
/// the conformance suite over it, and say whether it earns the badge.
///
///     dart run flutter3d_build:plugin_mcp
///
/// **Decision 20 of `tasks/0.9-plugins.md`: an agent creates, tests and runs
/// a plugin through conformance.** The three tools are the three steps a
/// person takes from a terminal — `flutter3d create plugin`, `dart test
/// test/conformance_test.dart`, reading what failed — offered to an agent
/// with the same words, so the skill shipped beside them reads the same for
/// either.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:flutter3d_mcp/kit.dart';
import 'package:yaml/yaml.dart';

import 'mcp_tool.dart';
import 'plugin_discovery.dart'
    show PluginDiscoveryException, markerEntries, markerOf, pluginMarkerKey;
import 'plugin_template.dart';

/// The version this server tells a client it is: the pubspec's.
const String pluginAuthorMcpVersion = '1.0.0-rc.1';

/// The version of this server's tools — names and input schemas — announced
/// beside [pluginAuthorMcpVersion]. It moves only when
/// `api/flutter3d_build.mcp` does: a minor for a new tool or optional
/// argument, a major for anything that breaks a caller.
///
/// **1.0.0 with the first stable release** (decided 2026-10-09, task F3 of
/// the architecture review): the minors it counted before were moves within
/// a surface nobody had been promised yet, and a host meeting 1.2.0 at a
/// first release would look for a 1.0 and 1.1 that never shipped.
const String pluginAuthorMcpSchemaVersion = '1.0.0';

/// What each of [pluginAuthorTools] does to the disk: `plugin.create`
/// writes a package, the other two only run and read.
const Map<String, ToolName> pluginAuthorToolNames = <String, ToolName>{
  'plugin.create': ToolName('plugin.create'),
  'plugin.conformance': ToolName('plugin.conformance', ToolHints.reads),
  'plugin.report': ToolName('plugin.report', ToolHints.reads),
};

/// The conformance suite [pluginConformanceChecks] make up, as
/// `flutter3d_conformance`'s `conformanceSuiteVersion` names it: the version
/// a badge earned here carries, `conformant@1.0`. A check added to the suite
/// arrives in a new suite version, and this moves with it.
const String _conformanceSuiteVersion = '1.0';

/// The checks of `flutter3d_conformance`'s plugin suite, by the word each
/// test's name carries — what [ConformanceRun.earnsBadge] counts.
///
/// **Written here rather than imported**, because the suite is a test
/// library: depending on it would make the `test` package a dependency of
/// every build hook. The names are the suite's `pluginCheckNames`.
const List<String> pluginConformanceChecks = <String>[
  'manifest',
  'switch',
  'determinism',
  'backends',
  'budget',
];

/// What a run of a program answered: its exit code and both streams.
typedef PluginProcessResult = ({int exitCode, String stdout, String stderr});

/// Runs [executable] with [arguments] in [workingDirectory].
///
/// **A seam, so the server's suite runs no process.** The real one is
/// [Process.run]; a test hands one that returns a canned reporter stream.
typedef PluginProcessRunner =
    Future<PluginProcessResult> Function(
      String executable,
      List<String> arguments,
      String workingDirectory,
    );

Future<PluginProcessResult> _runProcess(
  String executable,
  List<String> arguments,
  String workingDirectory,
) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  return (
    exitCode: result.exitCode,
    stdout: '${result.stdout}',
    stderr: '${result.stderr}',
  );
}

/// One test of a conformance run, as the JSON reporter told it.
final class ConformanceTest {
  const ConformanceTest({
    required this.name,
    required this.check,
    required this.passed,
    required this.declined,
    required this.says,
  });

  /// The test's full name, groups included.
  final String name;

  /// Which of [pluginConformanceChecks] it belongs to, or null for a test
  /// that is not one of the suite's.
  final String? check;

  /// Whether it passed. A declined test did not.
  final bool passed;

  /// Whether the suite skipped it: a determinism check with no world to
  /// step, a backend this machine cannot draw with.
  final bool declined;

  /// The error it failed with, or the reason it was skipped; empty when it
  /// passed.
  final String says;

  /// One line: a mark, the name, and what went wrong.
  String get line => switch ((passed, declined)) {
    (true, _) => 'passed  $name',
    (_, true) => 'declined  $name${says.isEmpty ? '' : ': $says'}',
    _ => 'failed  $name: ${says.isEmpty ? 'no reason given' : says}',
  };
}

/// The tests of [output], a `--reporter json` stream, in the order they
/// started.
///
/// Hidden tests — the loading of each suite file — are left out, unless one
/// failed: a suite that does not compile reports nothing but a failed load,
/// and that is the one line the author needs.
List<ConformanceTest> readJsonReporter(String output) {
  final names = <int, String>{};
  final order = <int>[];
  final done = <int, Map<String, Object?>>{};
  final errors = <int, List<String>>{};
  final skipReasons = <int, String>{};
  for (final line in const LineSplitter().convert(output)) {
    final Object? event;
    try {
      event = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (event is! Map<String, Object?>) continue;
    switch (event['type']) {
      case 'testStart':
        final test = event['test'];
        if (test is! Map<String, Object?>) continue;
        final id = test['id'];
        final name = test['name'];
        if (id is! int || name is! String) continue;
        names[id] = name;
        order.add(id);
        final skip = test['metadata'];
        if (skip is Map<String, Object?> && skip['skipReason'] is String) {
          skipReasons[id] = skip['skipReason']! as String;
        }
      case 'testDone':
        final id = event['testID'];
        if (id is int) done[id] = event;
      case 'error':
        final id = event['testID'];
        final error = event['error'];
        if (id is int && error is String) {
          (errors[id] ??= <String>[]).add(error);
        }
    }
  }
  return <ConformanceTest>[
    for (final id in order)
      if (done[id] case final Map<String, Object?> finished)
        if (finished['hidden'] != true || finished['result'] != 'success')
          _test(
            names[id]!,
            finished,
            errors[id] ?? const <String>[],
            skipReasons[id],
          ),
  ];
}

ConformanceTest _test(
  String name,
  Map<String, Object?> finished,
  List<String> errors,
  String? skipReason,
) {
  final skipped = finished['skipped'] == true;
  final passed = !skipped && finished['result'] == 'success';
  final lower = name.toLowerCase();
  final check = pluginConformanceChecks
      .where((String c) => RegExp('\\b$c\\b').hasMatch(lower))
      .firstOrNull;
  return ConformanceTest(
    name: name,
    check: check,
    passed: passed,
    declined: skipped,
    says: passed
        ? ''
        : skipped
        ? skipReason ?? ''
        : errors.map((String e) => e.split('\n').first).join('; '),
  );
}

/// One run of a plugin's conformance suite.
final class ConformanceRun {
  const ConformanceRun({required this.exitCode, required this.tests});

  /// What the test runner exited with.
  final int exitCode;

  /// Every test it reported.
  final List<ConformanceTest> tests;

  /// Whether the plugin earns the conformance badge on this run.
  ///
  /// **Every check run, and none of them failed or declined.** A declined
  /// check is a check not made — a determinism check with no world to step,
  /// a budget the manifest never declared — and a badge given for checks not
  /// made says nothing. `flutter3d_conformance`'s README states the same
  /// criterion for a person.
  bool get earnsBadge =>
      exitCode == 0 &&
      tests.isNotEmpty &&
      tests.every((ConformanceTest t) => t.passed) &&
      pluginConformanceChecks.every(
        (String check) => tests.any((ConformanceTest t) => t.check == check),
      );

  /// The badge this run earns, as it is written — `conformant@1.0`, naming
  /// the suite the checks belong to — or null when it earns none.
  String? get badge =>
      earnsBadge ? 'conformant@$_conformanceSuiteVersion' : null;

  /// The checks no test of this run covered.
  List<String> get missing => <String>[
    for (final check in pluginConformanceChecks)
      if (!tests.any((ConformanceTest t) => t.check == check)) check,
  ];
}

/// What the author server works on: the plugins it created or was pointed
/// at, and the last conformance run of each.
///
/// **No document, unlike every other server here.** A plugin is a package
/// on disk, so a tool names its directory and the session keeps only what a
/// later call needs — the last run, for `plugin.report`.
final class PluginWorkshop {
  PluginWorkshop({PluginProcessRunner? run}) : _run = run ?? _runProcess;

  final PluginProcessRunner _run;
  final Map<String, ConformanceRun> _runs = <String, ConformanceRun>{};

  /// The last conformance run in [directory], or null when there was none.
  ConformanceRun? lastRun(String directory) =>
      _runs[Directory(directory).absolute.path];

  /// Writes a new plugin of [kind] called [name] into [directory], which
  /// must be empty or not exist.
  Answer create(String directory, String name, PluginKind kind) {
    final target = Directory(directory);
    if (target.existsSync() && target.listSync().isNotEmpty) {
      return (
        did: false,
        says:
            '$directory is not empty; a plugin is created into a directory of '
            'its own, so nothing already there is written over',
      );
    }
    final files = pluginTemplate(name: name, kind: kind);
    for (final MapEntry(key: path, value: text) in files.entries) {
      File('${target.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
    }
    return (
      did: true,
      says:
          'wrote a $kind plugin into $directory: '
          '${files.keys.join(', ')}. Run `dart pub get` there, then '
          'plugin.conformance',
    );
  }

  /// Runs `test/conformance_test.dart` in [directory] and keeps the run.
  Future<Answer> conformance(String directory) async {
    final root = Directory(directory).absolute;
    final suite = File('${root.path}/test/conformance_test.dart');
    if (!suite.existsSync()) {
      return (
        did: false,
        says:
            '$directory has no test/conformance_test.dart. A plugin made by '
            'plugin.create has one; any other calls runPluginConformance '
            'from it',
      );
    }
    final pubspec = File('${root.path}/pubspec.yaml');
    final usesFlutter =
        pubspec.existsSync() &&
        RegExp(
          r'^\s+flutter:\s*\n\s+sdk:\s*flutter',
          multiLine: true,
        ).hasMatch(pubspec.readAsStringSync());
    final result = await _run(usesFlutter ? 'flutter' : 'dart', <String>[
      'test',
      'test/conformance_test.dart',
      '--reporter',
      'json',
    ], root.path);
    final tests = readJsonReporter(result.stdout);
    if (tests.isEmpty) {
      final why = result.stderr.trim().split('\n').take(12).join('\n');
      return (
        did: false,
        says:
            'the suite reported no tests (exit ${result.exitCode})'
            '${why.isEmpty ? '' : ':\n$why'}',
      );
    }
    final run = ConformanceRun(exitCode: result.exitCode, tests: tests);
    _runs[root.path] = run;
    final failed = tests.where((ConformanceTest t) => !t.passed).length;
    final badge = run.earnsBadge
        ? '; the plugin earns the badge ${run.badge}'
        : '';
    return (
      did: true,
      says: <String>[
        '${tests.length - failed} of ${tests.length} passed$badge',
        for (final test in tests) test.line,
      ].join('\n'),
    );
  }

  /// What the plugin in [directory] is, and how its last run went.
  Answer report(String directory) {
    final root = Directory(directory).absolute;
    final pubspec = File('${root.path}/pubspec.yaml');
    if (!pubspec.existsSync()) {
      return (did: false, says: '$directory has no pubspec.yaml');
    }
    final Object? document;
    try {
      document = loadYaml(pubspec.readAsStringSync());
    } on YamlException catch (error) {
      return (did: false, says: 'its pubspec does not read: ${error.message}');
    }
    final name = document is Map ? document['name'] : null;
    final marker = document is Map ? markerOf(document) : null;
    final lines = <String>[
      'package: ${name ?? '(no name)'}',
      switch (marker) {
        null => 'no `$pluginMarkerKey:` marker, so discovery will not find it',
        (final Object plugin, legacy: false) =>
          'plugin: ${_markerText('${name ?? ''}', plugin)}',
        (final Object plugin, legacy: true) =>
          'plugin: ${_markerText('${name ?? ''}', plugin)} (under the '
              'pre-1.0 `flutter3d: plugin:` key, read until 2.0: move it to '
              '`$pluginMarkerKey:`)',
      },
    ];
    final run = _runs[root.path];
    if (run == null) {
      lines.add('no conformance run yet: call plugin.conformance');
    } else {
      for (final check in pluginConformanceChecks) {
        final tests = run.tests.where((ConformanceTest t) => t.check == check);
        lines.add(switch (tests) {
          _ when tests.isEmpty => '$check: not run',
          _ when tests.every((ConformanceTest t) => t.passed) =>
            '$check: passed',
          _
              when tests.any((ConformanceTest t) => t.declined) &&
                  !tests.any((ConformanceTest t) => !t.passed && !t.declined) =>
            '$check: declined',
          _ => '$check: failed',
        });
      }
      lines.add(
        run.earnsBadge
            ? 'badge: ${run.badge} — every check of suite '
                  '$_conformanceSuiteVersion ran on every declared backend and '
                  'passed'
            : 'badge: not earned — every check has to run and pass, with a '
                  'world given to determinism and a budget declared and kept'
                  '${run.missing.isEmpty ? '' : ' (not run: ${run.missing.join(', ')})'}',
      );
    }
    return (did: true, says: lines.join('\n'));
  }
}

/// The entries a marker names, read as discovery reads them: one, a list,
/// or a map of library to classes all come out as `<import>#<Class>`. A
/// marker discovery would refuse says so instead.
String _markerText(String package, Object plugin) {
  try {
    return markerEntries(package, plugin).join(', ');
  } on PluginDiscoveryException catch (error) {
    return '$plugin, which discovery refuses: ${error.message}';
  }
}

/// A tool of the author server.
typedef PluginAuthorTool = OfferedTool<PluginWorkshop, Answer>;

StringSchema _directory(String about) => StringSchema(description: about);

/// The author server's tools, in the order `tools/list` gives them.
final List<PluginAuthorTool> pluginAuthorTools = <PluginAuthorTool>[
  PluginAuthorTool(
    mcpTool(
      name: 'plugin.create',
      description:
          'Write a new flutter3d plugin package from a template: a pubspec '
          'with the discovery marker, the plugin, a test that installs it '
          'and the conformance suite. The directory must be empty or not '
          'exist.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'directory': _directory('where the package is written'),
          'name': StringSchema(
            description:
                'the package name, which is also the plugin id: lower case, '
                'words joined by underscores',
          ),
          'kind': UntitledSingleSelectEnumSchema(
            description: <String>[
              for (final kind in PluginKind.values)
                '${kind.name}: ${kind.about}',
            ].join('; '),
            values: <String>[for (final kind in PluginKind.values) kind.name],
          ),
        },
        required: <String>['directory', 'name', 'kind'],
      ),
    ),
    (PluginWorkshop workshop, Map<String, Object?> arguments) =>
        workshop.create(
          arguments['directory']! as String,
          arguments['name']! as String,
          PluginKind.named(arguments['kind']! as String),
        ),
  ),
  PluginAuthorTool(
    mcpTool(
      name: 'plugin.conformance',
      description:
          'Run the plugin\'s conformance suite (test/conformance_test.dart) '
          'and say, test by test, what passed, failed or was declined. Run '
          '`dart pub get` in the directory first.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'directory': _directory('the plugin package'),
        },
        required: <String>['directory'],
      ),
    ),
    (PluginWorkshop workshop, Map<String, Object?> arguments) =>
        workshop.conformance(arguments['directory']! as String),
  ),
  PluginAuthorTool(
    mcpTool(
      name: 'plugin.report',
      description:
          'Say what the plugin package is — its name and discovery marker — '
          'how each check went in its last conformance run, and whether it '
          'earns the conformance badge.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'directory': _directory('the plugin package'),
        },
        required: <String>['directory'],
      ),
    ),
    (PluginWorkshop workshop, Map<String, Object?> arguments) =>
        workshop.report(arguments['directory']! as String),
  ),
];

/// Creating, checking and reporting on a flutter3d plugin, offered to an
/// agent as a table of tools.
///
/// **No window and no engine.** A plugin is checked by its own suite in its
/// own process, so this server only writes files and starts that process;
/// what the checks mean is `flutter3d_conformance`'s.
base class PluginAuthorMcpServer
    extends ToolTableServer<PluginWorkshop, Answer> {
  PluginAuthorMcpServer(super.channel, {required super.session})
    : super(
        name: 'flutter3d.plugins',
        version: pluginAuthorMcpVersion,
        schemaVersion: pluginAuthorMcpSchemaVersion,
        names: pluginAuthorToolNames,
        instructions: _instructions,
        tools: pluginAuthorTools,
        toResult: resultOf,
      );
}

const String _instructions = '''
Write a flutter3d plugin and check it. `plugin.create` writes a package from a
template — render-step, effect, genre, element or tool. Run `dart pub get` in
it, edit the plugin, then call `plugin.conformance`, which runs its suite:
the manifest, switching on and off at a step boundary, determinism (each step
run twice from a snapshot), every declared backend, and the budget in the
manifest. `plugin.report` says how each check went and whether the plugin
earns the badge, which needs every check run and passed.''';
