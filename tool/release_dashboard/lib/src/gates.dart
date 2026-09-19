/// The checks the repository already has, and how to read what they print.
///
/// Nothing here is a second implementation of a rule. Each gate runs the script
/// CI runs and turns its output into a level and a sentence, so the dashboard
/// and the pipeline cannot disagree about what "green" means; a rule changed in
/// `tool/structure/` changes what this shows with no edit here.
library;

import 'dart:io';

import 'model.dart';
import 'shell.dart';

/// Turns a finished run into a result.
typedef Judge = GateResult Function(Ran ran);

/// One script the dashboard can run.
final class Gate {
  const Gate({
    required this.id,
    required this.title,
    required this.command,
    required this.judge,
    this.auto = false,
    this.timeout = const Duration(minutes: 3),
  });

  final String id;
  final String title;
  final List<String> command;
  final Judge judge;

  /// Whether the dashboard runs it by itself when the tree changes. Only the
  /// checks that take seconds are: the rest are asked for by a click.
  final bool auto;
  final Duration timeout;

  /// The same gate, run only when somebody asks.
  Gate withoutAuto() => Gate(
    id: id,
    title: title,
    command: command,
    judge: judge,
    timeout: timeout,
  );
}

/// The name `tool/structure.dart` gives to the rule about test counts.
const String testCountRule = 'the document says how many tests there are';

GateResult _judgeFormat(Ran ran) {
  final changed = ran.lines.where((l) => l.startsWith('Changed ')).length;
  if (ran.ok) {
    return GateResult(
      level: Level.pass,
      summary: ran.lines.isEmpty ? 'formatted' : ran.tail(1).first,
      tail: ran.tail(),
    );
  }
  return GateResult(
    level: Level.fail,
    summary: changed > 0
        ? '$changed files are not formatted'
        : _reason(ran, 'dart format failed'),
    tail: ran.tail(),
  );
}

GateResult _judgeStructure(Ran ran) {
  final broken = <String>[
    for (final line in ran.lines)
      if (line.startsWith('✗ ')) line.substring(2).trim(),
  ];
  final summary = ran.tail(1).firstOrNull ?? 'no output';
  if (ran.ok && broken.isEmpty) {
    return GateResult(level: Level.pass, summary: summary, tail: ran.tail());
  }
  return GateResult(
    level: Level.fail,
    summary: broken.isEmpty ? _reason(ran, summary) : summary,
    brokenRules: broken,
    tail: ran.tail(),
  );
}

GateResult _judgeAnalyze(Ran ran) {
  final clean = ran.lines.any((l) => l.contains('No issues found'));
  if (ran.ok && clean) {
    return GateResult(
      level: Level.pass,
      summary: 'no issues found',
      tail: ran.tail(),
    );
  }
  final counted = ran.lines
      .map((l) => RegExp(r'(\d+) issues? found').firstMatch(l))
      .whereType<RegExpMatch>()
      .firstOrNull;
  return GateResult(
    level: Level.fail,
    summary: counted == null
        ? _reason(ran, 'analysis failed')
        : '${counted.group(1)} issues',
    tail: ran.tail(),
  );
}

GateResult _judgePublishCheck(Ran ran) {
  final ready = ran.lines.where((l) => RegExp(r'\bready\s*$').hasMatch(l));
  if (ran.ok) {
    return GateResult(
      level: Level.pass,
      summary: '${ready.length} packages ready to publish',
      tail: ran.tail(),
    );
  }
  final refused = ran.lines
      .where((l) => l.contains('doesn\'t mention') || l.contains('ERROR'))
      .length;
  return GateResult(
    level: Level.fail,
    summary: refused > 0
        ? '$refused problems in the dry run'
        : _reason(ran, 'publish check failed'),
    tail: ran.tail(),
  );
}

/// A gate whose whole answer is the script's exit code.
Judge _judgeExit(String passed, String failed) {
  return (Ran ran) => ran.ok
      ? GateResult(level: Level.pass, summary: passed, tail: ran.tail())
      : GateResult(
          level: Level.fail,
          summary: _reason(ran, failed),
          tail: ran.tail(),
        );
}

/// The one line that says why a run failed, when nothing more specific does.
String _reason(Ran ran, String fallback) {
  if (ran.timedOut) return 'timed out after ${ran.duration.inSeconds} s';
  if (ran.failedToStart) return ran.lines.firstOrNull ?? 'could not start';
  return ran.tail(1).firstOrNull ?? fallback;
}

const String _webBuild =
    'cd apps/flutter3d_modeler && flutter build web --release '
    '--base-href=/app/ --no-web-resources-cdn '
    '--dart-define=FLUTTER3D_WEBGPU=true';

const String _showcaseWeb =
    'cd apps/flutter3d_showcase && flutter build web --release '
    '--base-href=/showcase/ --no-web-resources-cdn '
    '--dart-define=FLUTTER3D_WEBGPU=true';

/// The gates, in the order the page lists them.
List<Gate> defaultGates(Directory root) => <Gate>[
  const Gate(
    id: 'format',
    title: 'dart format',
    command: <String>[
      'dart',
      'format',
      '--output=none',
      '--set-exit-if-changed',
      'packages',
      'apps',
      'tool',
    ],
    judge: _judgeFormat,
    auto: true,
    timeout: Duration(minutes: 2),
  ),
  const Gate(
    id: 'structure',
    title: 'tool/structure.dart',
    command: <String>['dart', 'run', 'tool/structure.dart'],
    judge: _judgeStructure,
    auto: true,
  ),
  Gate(
    id: 'plan',
    title: 'tool/verify_plan.dart',
    command: const <String>['dart', 'run', 'tool/verify_plan.dart'],
    judge: _judgeExit('every finished row names something real', 'plan check'),
    auto: true,
  ),
  const Gate(
    id: 'analyze',
    title: 'flutter analyze',
    command: <String>['flutter', 'analyze'],
    judge: _judgeAnalyze,
    auto: true,
    timeout: Duration(minutes: 5),
  ),
  const Gate(
    id: 'publish',
    title: 'publish dry run, all packages',
    command: <String>['bash', 'tool/publish_check.sh'],
    judge: _judgePublishCheck,
    timeout: Duration(minutes: 10),
  ),
  Gate(
    id: 'web',
    title: 'modeller web build',
    command: const <String>['bash', '-c', _webBuild],
    judge: _judgeExit('dart2js built the modeller', 'web build failed'),
    timeout: Duration(minutes: 15),
  ),
  Gate(
    id: 'showcase-web',
    title: 'showcase web build',
    command: const <String>['bash', '-c', _showcaseWeb],
    judge: _judgeExit(
      'dart2js built the showcase',
      'showcase web build failed',
    ),
    timeout: Duration(minutes: 15),
  ),
  Gate(
    id: 'showcase-tests',
    title: 'showcase tests',
    command: const <String>[
      'bash',
      '-c',
      'cd apps/flutter3d_showcase && flutter test',
    ],
    judge: _judgeExit('the showcase tests pass', 'showcase tests failed'),
    timeout: Duration(minutes: 20),
  ),
  Gate(
    id: 'ci',
    title: 'tool/ci.sh, everything CI runs here',
    command: const <String>['bash', 'tool/ci.sh'],
    judge: _judgeExit('the whole local pipeline passed', 'tool/ci.sh failed'),
    timeout: Duration(minutes: 90),
  ),
];
