/// What a flutter3d plugin has to do, as checks it runs against itself.
///
/// **The other half of this package.** `flutter3d_conformance.dart` holds a
/// backend to what `flutter3d_hardware` cannot say in a signature; this holds
/// a plugin to what `flutter3d_plugin_api` cannot: that it says what it is,
/// that switching it off takes back everything it added, that a step it runs
/// gives one answer, that it runs where it says it runs, and that it costs
/// what it says it costs, and that a substance it brings is one the engine
/// can trust. Decision 20 of `tasks/0.9-plugins.md`.
///
/// ```dart
/// import 'package:flutter3d_conformance/plugins.dart';
///
/// void main() => runPluginConformance(
///   WindPlugin.new,
///   harness: PluginHarness(
///     setUp: (loop) => loop
///       ..snapshots.add(world.snapshotPart)
///       ..addSystem('world', LoopPhase.physics, world.step),
///   ),
/// );
/// ```
///
/// ## The 8 plugin checks
///
/// * **plugin.manifest** — the id is well formed, the plugin API version installs on
///   this engine, every permission is one the engine knows, a budget reads,
///   the manifest is the same written out and read back, and the plugin
///   installs: a view plugin that adds a step system is refused here, with
///   the loop's own sentence.
/// * **plugin.switch** — switched off at a step boundary, the loop's phases, systems,
///   declared events, fields and subsystems are exactly those of a loop
///   without it; switched
///   back on, exactly those with it; both journalled at the step they were
///   made.
/// * **plugin.names** — every phase, system, event, field and subsystem it adds to
///   the loop is in its namespace, `<namespace>.<name>`; the engine's own packages are not held
///   to one.
/// * **plugin.determinism** — every step run twice from one state by the loop's
///   `DeterminismCheck`, which names the system that diverged; and two fresh
///   runs publish the same events and leave the same world, step by step.
/// * **plugin.backends** — installed and stepped on every backend the manifest
///   names (on none and all four when it names none), and switched off with
///   a reason on one it does not.
/// * **plugin.budget** — no step publishes more events than the manifest's budget
///   allows, and the median cost of a step with the plugin, less without it,
///   is within its `stepMicroseconds`.
/// * **plugin.materials** — every physical material it adds to the engine's
///   `MaterialCatalog` is under its own id, names a source for each group,
///   says a liquid's or a gas's density and viscosity and keeps every number
///   in SI within what anything real has (`PhysicalMaterial.problems`);
///   every pair it measures has one of its own in it and a source; and all of
///   it is gone when it is switched off. A plugin that brings none passes.
/// * **plugin.render** — installed on the software backend with the
///   harness's registries, whether the plugin places nodes in the frame:
///   one that does names `render.nodes` in its outcome's `requires`, and the
///   render suite's checks on `cpu` are then part of its badge.
///
/// ## The badge
///
/// **flutter3d conformant@1.0**: `checkPluginConformance` passes every check
/// of suite 1.0 on every declared backend, with a world given to determinism
/// and a budget declared and kept, on the plugin API version in its
/// manifest. [earnsBadge] answers it and [badgeFor] names it. A declined
/// check — no world, no budget, assertions off — is never green and keeps
/// the badge away, because a check that was not asked has not been passed.
///
/// **Render conformance counts for a plugin that draws.** A plugin that
/// places nodes in the frame (`plugin.render`) earns the badge only with the
/// render checks it requires passed on the software backend, `cpu`
/// (`runPluginRenderConformance` of `flutter3d_conformance_render`), and a
/// plugin of any kind keeps it only while no render check it ran failed on
/// any backend. The two suites write one report: each keeps the other's
/// outcomes in `<package>.conformance.json` and replaces its own, so the
/// badge in it is judged on both, whichever ran last.
///
/// **The badge names the suite it was earned against.** A check added later
/// joins a new suite version, never an old one, so a plugin that earned
/// `conformant@1.0` keeps it when this package grows; it earns
/// `conformant@1.1` by passing the larger suite.
///
/// ```markdown
/// ![flutter3d conformant@1.0](https://img.shields.io/badge/flutter3d-conformant%401.0-2ea44f)
/// ```
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Flutter3dPlugin, FormatSpec;
import 'package:test/test.dart' show fail, markTestSkipped, tearDownAll, test;

import 'src/plugins/harness.dart';
import 'src/plugins/plugin_checks.dart';
import 'src/plugins/report_file.dart'
    if (dart.library.io) 'src/plugins/report_file_io.dart';

export 'src/plugins/harness.dart'
    show PluginBudget, PluginCheckOutcome, PluginHarness;

/// The checks' names, in the order they are reported.
const List<String> pluginCheckNames = <String>[
  'plugin.manifest',
  'plugin.switch',
  'plugin.names',
  'plugin.determinism',
  'plugin.backends',
  'plugin.budget',
  'plugin.materials',
  'plugin.render',
];

/// Runs every plugin check against the plugin [create] makes, and returns
/// what each found — one outcome per check, and one per backend for the
/// backends check.
///
/// For a tool or a script that reports rather than a suite that fails, and
/// for [earnsBadge]. [runPluginConformance] is the same checks as tests.
List<PluginCheckOutcome> checkPluginConformance(
  Flutter3dPlugin Function() create, {
  PluginHarness harness = const PluginHarness(),
}) {
  final session = PluginSession(create, harness);
  return <PluginCheckOutcome>[
    for (final check in pluginChecks) ...check.run(session),
  ];
}

/// The suite this package's checks make up: the version a badge earned
/// with them names.
const String conformanceSuiteVersion = '1.0';

/// Every suite version, with the checks it is made of.
///
/// **Append-only.** A new check goes into a new suite version, listed here
/// with every check of the one before it; a suite once listed never changes,
/// so a badge earned against it keeps meaning the same thing. (`materials`
/// and `names` joined 1.0 before 1.0 was released, so no badge was earned
/// without them.)
const Map<String, List<String>> conformanceSuites = <String, List<String>>{
  '1.0': pluginCheckNames,
};

/// Whether [outcomes] earn the badge of [suite]: every check of that suite
/// ran, every one passed and none declined; every check an outcome
/// [PluginCheckOutcome.requires] — the render checks of a plugin that draws
/// — passed on the software backend, `cpu`, and was not declined there; and
/// no render check failed on any backend.
bool earnsBadge(
  List<PluginCheckOutcome> outcomes, {
  String suite = conformanceSuiteVersion,
}) {
  final checks = conformanceSuites[suite];
  if (checks == null) {
    throw ArgumentError.value(
      suite,
      'suite',
      'is not a conformance suite; there are ${conformanceSuites.keys.join(', ')}',
    );
  }
  final ran = outcomes.where((o) => checks.contains(o.check)).toList();
  final required = <String>{for (final o in ran) ...o.requires};
  return ran.isNotEmpty &&
      checks.every((name) => ran.any((o) => o.check == name)) &&
      ran.every((o) => o.passed && !o.declined) &&
      required.every(
        (name) => outcomes.any(
          (o) =>
              o.check == name &&
              o.backend == renderBadgeBackend &&
              o.passed &&
              !o.declined,
        ),
      ) &&
      !outcomes.any(
        (o) => o.check.startsWith('render.') && !o.passed && !o.declined,
      );
}

/// The backend a render check a badge requires is passed on: the software
/// rasteriser, which every machine has and CI runs on every change.
const String renderBadgeBackend = 'cpu';

/// The badge [outcomes] earn, as it is written — `conformant@1.0` — for the
/// newest suite they pass; null when they pass none.
String? badgeFor(List<PluginCheckOutcome> outcomes) {
  final suites = conformanceSuites.keys.toList().reversed;
  for (final suite in suites) {
    if (earnsBadge(outcomes, suite: suite)) return 'conformant@$suite';
  }
  return null;
}

/// The conformance report's format: what [conformanceReport] writes and a
/// catalogue or a CI job reads.
const FormatSpec conformanceReportFormat = FormatSpec(
  id: 'f3d.conformance',
  version: 1,
  suffixes: <String>['.conformance.json'],
  fixture: 'test/fixtures/v<N>/glow.conformance.json',
);

/// [outcomes] as a JSON document in the format envelope: the suite, the
/// badge, and each outcome.
///
/// `{"format": "f3d.conformance", "version": 1, "requires": [],
/// "generator": "flutter3d_conformance", "plugin": ..., "suite": "1.0",
/// "badge": "conformant@1.0" | null, "outcomes": [...]}`. Keys are only
/// added within a version.
Map<String, Object?> conformanceReport(
  String plugin,
  List<PluginCheckOutcome> outcomes,
) => <String, Object?>{
  ...conformanceReportFormat.envelope(generator: 'flutter3d_conformance'),
  'plugin': plugin,
  'suite': conformanceSuiteVersion,
  'badge': badgeFor(outcomes),
  'outcomes': <Object?>[
    for (final o in outcomes)
      <String, Object?>{
        'check': o.check,
        'backend': ?o.backend,
        'passed': o.passed,
        'declined': o.declined,
        'says': o.says,
        if (o.requires.isNotEmpty) 'requires': o.requires,
      },
  ],
};

/// [ran] in place of the outcomes of [isOurs] in the report already in the
/// package, if there is one: what a suite writes, so the plugin suite and
/// the render suite, each in a test file of its own, leave one report
/// holding both, judged by [earnsBadge] on both.
List<PluginCheckOutcome> mergedOutcomes(
  String plugin,
  List<PluginCheckOutcome> ran, {
  required bool Function(PluginCheckOutcome outcome) isOurs,
}) => <PluginCheckOutcome>[
  for (final json in readConformanceReportOutcomes(plugin))
    if (PluginCheckOutcome.fromJson(json) case final kept? when !isOurs(kept))
      kept,
  ...ran,
];

/// Writes [ran], the render checks' outcomes of [plugin] on the backends
/// they ran on, into the package's `<package>.conformance.json`, beside
/// the plugin suite's and replacing the render outcomes of those backends,
/// with the badge judged again on all of them. What
/// `runPluginRenderConformance` calls once its checks are done.
void recordRenderOutcomes(String plugin, List<PluginCheckOutcome> ran) {
  final backends = <String?>{for (final o in ran) o.backend};
  final merged = mergedOutcomes(
    plugin,
    ran,
    isOurs: (o) =>
        o.check.startsWith('render.') && backends.contains(o.backend),
  );
  writeConformanceReportFile(plugin, () => conformanceReport(plugin, merged));
}

/// What every [runPluginConformance] of this test run found so far, in the
/// order its checks ran: the outcomes the report file is written from.
final List<PluginCheckOutcome> _reported = <PluginCheckOutcome>[];

/// Registers the plugin checks as tests: one per check, and one per backend
/// for the backends check, named "plugin.backends on webgl".
///
/// A declined check is reported as skipped with its reason, as
/// `runDeviceConformance` reports a backend that declines: never as a pass.
///
/// **Writes `<package>.conformance.json`** (`f3d.conformance`, the
/// [conformanceReport] of what ran) beside the pubspec of the package the
/// suite runs in, once its checks are done: the one record of whether the
/// plugin earns the badge, judged by [earnsBadge] and read by
/// `flutter3d_build`'s `plugin.report` and the plugin catalogue. A suite
/// that calls this more than once (under two profiles, say) writes one
/// file holding every outcome, and earns the badge only if every call
/// would. A check left out by `--name` is not run, so the file of a
/// partial run earns nothing. In a browser nothing is written.
void runPluginConformance(
  Flutter3dPlugin Function() create, {
  PluginHarness harness = const PluginHarness(),
}) {
  final session = PluginSession(create, harness);
  final found = <String, List<PluginCheckOutcome>>{};
  tearDownAll(() {
    for (final check in pluginChecks) {
      _reported.addAll(found[check.name] ?? const <PluginCheckOutcome>[]);
    }
    found.clear();
    final plugin = session.manifest.id;
    // The render suite's outcomes, if it ran first, stay beside these.
    final merged = mergedOutcomes(
      plugin,
      _reported,
      isOurs: (o) => !o.check.startsWith('render.'),
    );
    writeConformanceReportFile(plugin, () => conformanceReport(plugin, merged));
  });
  final declared = session.manifest.backends.toList();
  for (final check in pluginChecks) {
    List<PluginCheckOutcome> outcomes() =>
        found.putIfAbsent(check.name, () => check.run(session));
    void report(PluginCheckOutcome? outcome) {
      if (outcome == null) {
        fail('${check.name} reported nothing');
      }
      if (outcome.declined) {
        markTestSkipped(outcome.says);
        return;
      }
      if (!outcome.passed) fail(outcome.says);
    }

    if (check.name != 'plugin.backends') {
      test(check.name, () => report(outcomes().firstOrNull));
      continue;
    }
    // The backends are known before anything runs — from the manifest — so
    // each gets a test of its own, and the one the plugin does not declare
    // is whichever the check picks, reported under the last name.
    final backends = <String?>[
      ...(declared.isEmpty ? everyBackend : declared),
      if (declared.isNotEmpty) 'undeclared',
    ];
    for (var i = 0; i < backends.length; i++) {
      test('plugin.backends on ${backends[i] ?? 'no backend'}', () {
        final all = outcomes();
        report(i < all.length ? all[i] : null);
      });
    }
  }
}
