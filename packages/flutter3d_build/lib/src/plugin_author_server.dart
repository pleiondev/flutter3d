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
    show
        PluginDiscoveryException,
        PluginMarker,
        markerEntries,
        markerOf,
        pluginMarkerKey;
import 'plugin_template.dart';

/// The version this server tells a client it is: the pubspec's.
const String pluginAuthorMcpVersion = '1.0.0-rc.1+1';

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
/// writes a package, the other two only run and read (the suite
/// `plugin.conformance` runs writes its own report).
const Map<String, ToolName> pluginAuthorToolNames = <String, ToolName>{
  'plugin.create': ToolName('plugin.create'),
  'plugin.conformance': ToolName('plugin.conformance', hints: ToolHints.reads),
  'plugin.report': ToolName('plugin.report', hints: ToolHints.reads),
};

/// The newest version of the `f3d.conformance` report this server reads,
/// as `flutter3d_conformance`'s `conformanceReportFormat` writes it.
const int _reportVersion = 1;

/// One outcome of a conformance report: a check, on a backend for the
/// backends check, and how it went.
final class ConformanceOutcome {
  const ConformanceOutcome({
    required this.check,
    this.backend,
    required this.passed,
    required this.declined,
    required this.says,
  });

  /// The check's name, as the suite reports it.
  final String check;

  /// The backend it ran on, for the backends check; null for the others.
  final String? backend;

  /// Whether it passed. A declined check did not.
  final bool passed;

  /// Whether the suite declined it: no world for determinism, no budget.
  final bool declined;

  /// What the check found, in a sentence.
  final String says;
}

/// A plugin's `<package>.conformance.json`: what its conformance suite
/// found, and the badge `flutter3d_conformance`'s `earnsBadge` gave it.
///
/// **The suite is the only judge.** `runPluginConformance` writes this file
/// once its checks have run, with the badge decided there; this server and
/// the plugin catalogue read it and decide nothing. A copy of the suite's
/// check list kept here could only disagree with it, and once did: it
/// counted five checks where the suite counted seven.
final class ConformanceReportFile {
  const ConformanceReportFile({
    required this.path,
    required this.plugin,
    required this.suite,
    required this.badge,
    required this.outcomes,
  });

  /// The file it was read from.
  final String path;

  /// The plugin's id, as its manifest says it.
  final String plugin;

  /// The suite version the checks belong to, such as `1.0`.
  final String suite;

  /// The badge the run earned, `conformant@1.0`, or null for none.
  final String? badge;

  /// Every outcome, in the order the checks ran.
  final List<ConformanceOutcome> outcomes;

  /// The report of [package] in [directory], `<package>.conformance.json`,
  /// or null when there is none: absent, since a plugin whose suite has not
  /// run has no report yet.
  ///
  /// Throws a [FormatException] for a file that is not an `f3d.conformance`
  /// report this reads, saying why.
  static ConformanceReportFile? readIn(String directory, String package) {
    final file = File('$directory/$package.conformance.json');
    if (!file.existsSync()) return null;
    final Object? json;
    try {
      json = jsonDecode(file.readAsStringSync());
    } on FormatException catch (error) {
      throw FormatException('${file.path} is not JSON: ${error.message}');
    }
    if (json is! Map<String, Object?> || json['format'] != 'f3d.conformance') {
      throw FormatException('${file.path} is not an f3d.conformance report');
    }
    final version = json['version'];
    if (version is! int || version > _reportVersion) {
      throw FormatException(
        '${file.path} is f3d.conformance version $version, newer than this '
        'build reads ($_reportVersion): update flutter3d_build',
      );
    }
    final outcomes = json['outcomes'];
    return ConformanceReportFile(
      path: file.path,
      plugin: '${json['plugin'] ?? package}',
      suite: '${json['suite'] ?? ''}',
      badge: json['badge'] is String ? json['badge']! as String : null,
      outcomes: <ConformanceOutcome>[
        if (outcomes is List)
          for (final outcome in outcomes.whereType<Map<String, Object?>>())
            ConformanceOutcome(
              check: '${outcome['check']}',
              backend: outcome['backend'] is String
                  ? outcome['backend']! as String
                  : null,
              passed: outcome['passed'] == true,
              declined: outcome['declined'] == true,
              says: '${outcome['says'] ?? ''}',
            ),
      ],
    );
  }

  /// One line a check, in the order the checks ran: passed, declined or
  /// failed, with what a failed one found.
  List<String> get lines => <String>[
    for (final check in <String>{for (final o in outcomes) o.check})
      _line(check, <ConformanceOutcome>[
        for (final o in outcomes)
          if (o.check == check) o,
      ]),
  ];

  static String _line(String check, List<ConformanceOutcome> ran) {
    final failed = ran
        .where((ConformanceOutcome o) => !o.passed && !o.declined)
        .firstOrNull;
    return switch (failed) {
      _ when ran.every((ConformanceOutcome o) => o.passed) => '$check: passed',
      final ConformanceOutcome o => '$check: failed — ${o.says}',
      null => '$check: declined',
    };
  }
}

/// What a run of a program answered: its exit code and both streams.
///
/// A class rather than a record, so a run can later report more (how long
/// it took) without breaking a runner written against it.
final class PluginProcessResult {
  const PluginProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// The program's exit code.
  final int exitCode;

  /// What it wrote to standard output.
  final String stdout;

  /// What it wrote to standard error.
  final String stderr;
}

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
  return PluginProcessResult(
    exitCode: result.exitCode,
    stdout: '${result.stdout}',
    stderr: '${result.stderr}',
  );
}

/// One test of a conformance run, as the JSON reporter told it.
final class ConformanceTest {
  const ConformanceTest({
    required this.name,
    required this.passed,
    required this.declined,
    required this.says,
  });

  /// The test's full name, groups included. Which check it is, the suite
  /// says in its report ([ConformanceReportFile]), not a word in this.
  final String name;

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
  return ConformanceTest(
    name: name,
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
  const ConformanceRun({
    required this.exitCode,
    required this.tests,
    this.report,
  });

  /// What the test runner exited with.
  final int exitCode;

  /// Every test it reported.
  final List<ConformanceTest> tests;

  /// The `<package>.conformance.json` the suite wrote, or null when it
  /// wrote none (a suite that does not call `runPluginConformance`, or one
  /// that did not compile).
  final ConformanceReportFile? report;

  /// The badge the suite's report gives, `conformant@1.0`, or null for
  /// none. Read, never decided here: `earnsBadge` in
  /// `flutter3d_conformance` is the judge.
  String? get badge => report?.badge;
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
      return Answer(
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
    return Answer(
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
      return Answer(
        did: false,
        says:
            '$directory has no test/conformance_test.dart. A plugin made by '
            'plugin.create has one; any other calls runPluginConformance '
            'from it',
      );
    }
    final pubspec = File('${root.path}/pubspec.yaml');
    final pubspecText = pubspec.existsSync() ? pubspec.readAsStringSync() : '';
    final usesFlutter = RegExp(
      r'^\s+flutter:\s*\n\s+sdk:\s*flutter',
      multiLine: true,
    ).hasMatch(pubspecText);
    final package = _packageName(pubspecText);
    // The report of an earlier run is not this run's: gone before the
    // suite starts, it cannot be read as the answer of a suite that then
    // failed to compile.
    final previous = File('${root.path}/$package.conformance.json');
    if (previous.existsSync()) previous.deleteSync();
    final result = await _run(usesFlutter ? 'flutter' : 'dart', <String>[
      'test',
      'test/conformance_test.dart',
      '--reporter',
      'json',
    ], root.path);
    final tests = readJsonReporter(result.stdout);
    if (tests.isEmpty) {
      final why = result.stderr.trim().split('\n').take(12).join('\n');
      return Answer(
        did: false,
        says:
            'the suite reported no tests (exit ${result.exitCode})'
            '${why.isEmpty ? '' : ':\n$why'}',
      );
    }
    final ConformanceReportFile? report;
    try {
      report = ConformanceReportFile.readIn(root.path, package);
    } on FormatException catch (error) {
      return Answer(did: false, says: error.message);
    }
    final run = ConformanceRun(
      exitCode: result.exitCode,
      tests: tests,
      report: report,
    );
    _runs[root.path] = run;
    final failed = tests.where((ConformanceTest t) => !t.passed).length;
    final badge = switch (report) {
      null => '; the suite wrote no $package.conformance.json, so no badge',
      ConformanceReportFile(badge: final String badge) =>
        '; the plugin earns the badge $badge',
      _ => '',
    };
    return Answer(
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
      return Answer(did: false, says: '$directory has no pubspec.yaml');
    }
    final Object? document;
    try {
      document = loadYaml(pubspec.readAsStringSync());
    } on YamlException catch (error) {
      return Answer(
        did: false,
        says: 'its pubspec does not read: ${error.message}',
      );
    }
    final name = document is Map ? document['name'] : null;
    final marker = document is Map ? markerOf(document) : null;
    final lines = <String>[
      'package: ${name ?? '(no name)'}',
      switch (marker) {
        null => 'no `$pluginMarkerKey:` marker, so discovery will not find it',
        PluginMarker(value: final Object plugin, legacy: false) =>
          'plugin: ${_markerText('${name ?? ''}', plugin)}',
        PluginMarker(value: final Object plugin, legacy: true) =>
          'plugin: ${_markerText('${name ?? ''}', plugin)} (under the '
              'pre-1.0 `flutter3d: plugin:` key, read until 2.0: move it to '
              '`$pluginMarkerKey:`)',
      },
    ];
    // What the suite last wrote, from the disk rather than this session:
    // the same file the catalogue reads, whoever ran the suite.
    final package = name is String ? name : _packageName('');
    final ConformanceReportFile? report;
    try {
      report = ConformanceReportFile.readIn(root.path, package);
    } on FormatException catch (error) {
      return Answer(did: false, says: error.message);
    }
    if (report == null) {
      lines.add(
        'no conformance report yet ($package.conformance.json, which the '
        'suite writes): call plugin.conformance',
      );
    } else {
      lines
        ..addAll(report.lines)
        ..add(switch (report.badge) {
          final String badge =>
            'badge: $badge — every check of suite ${report.suite} ran on '
                'every declared backend and passed, as '
                '${report.path.split('/').last} records',
          null =>
            'badge: not earned — every check of suite ${report.suite} has to '
                'run and pass, with a world given to determinism and a budget '
                'declared and kept, as ${report.path.split('/').last} records',
        });
    }
    return Answer(did: true, says: lines.join('\n'));
  }
}

/// The package [pubspec] names, which is the report's file name; `plugin`
/// when it names none.
String _packageName(String pubspec) =>
    RegExp(
      r'^name:\s*([a-z0-9_]+)',
      multiLine: true,
    ).firstMatch(pubspec)?.group(1) ??
    'plugin';

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

/// A [PluginAuthorTool] whose body reads the session and the arguments as two values,
/// the way every tool here is written.
PluginAuthorTool _tool(
  ToolSpec spec,
  FutureOr<Answer> Function(
    PluginWorkshop session,
    Map<String, Object?> arguments,
  )
  run,
) => PluginAuthorTool(spec, (call) => run(call.session, call.arguments));

StringSchema _directory(String about) => StringSchema(description: about);

/// The author server's tools, in the order `tools/list` gives them.
final List<PluginAuthorTool> pluginAuthorTools = <PluginAuthorTool>[
  _tool(
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
  _tool(
    mcpTool(
      name: 'plugin.conformance',
      description:
          'Run the plugin\'s conformance suite (test/conformance_test.dart) '
          'and say, test by test, what passed, failed or was declined. The '
          'suite writes <package>.conformance.json beside the pubspec, with '
          'the badge it judged. Run `dart pub get` in the directory first.',
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
  _tool(
    mcpTool(
      name: 'plugin.report',
      description:
          'Say what the plugin package is — its name and discovery marker — '
          'how each check went in its last conformance run, and whether it '
          'earns the conformance badge. Read from the '
          '<package>.conformance.json its suite wrote, which is the judge.',
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
template — render-step, effect, genre, element, tool, or backend for a graphics
backend held to the device suite. Run `dart pub get` in
it, edit the plugin, then call `plugin.conformance`, which runs its suite:
the manifest, switching on and off at a step boundary, determinism (each step
run twice from a snapshot), every declared backend, and the budget in the
manifest. The suite writes `<package>.conformance.json` with the badge it
judged; `plugin.report` reads that file and says how each check went and
whether the plugin earns the badge, which needs every check run and passed.''';
