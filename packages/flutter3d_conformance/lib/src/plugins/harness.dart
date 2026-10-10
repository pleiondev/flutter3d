import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// What a plugin's conformance run is given besides the plugin: the world
/// it acts on, the registries it asks for, and the application around it.
///
/// **The world is the loop's.** What the plugin acts on is captured,
/// restored and digested through the loop's own snapshots
/// (`EngineLoop.snapshots`), the one path a rollback and a replay take: so
/// [setUp] puts the application's state in `loop.world`, or adds a
/// `SnapshotPart` for state it keeps elsewhere (`loop.snapshots.add`), and
/// a plugin that keeps state of its own adds its part when it is installed.
/// A check never takes a second pair of functions that could disagree with
/// what a rollback restores.
///
/// **Everything optional, and what is left out is said rather than
/// assumed.** A plugin whose loop holds nothing — no entity, no resource, no
/// part — passes with nothing here, but determinism is then compared on its
/// events alone, the outcome says the world was not compared, and the badge
/// waits for a world (`earnsBadge`).
final class PluginHarness {
  const PluginHarness({
    this.registries,
    this.setUp,
    this.dependencies,
    this.steps = 600,
  }) : assert(steps > 0, 'a run of nought steps checks nothing');

  /// The registries the plugin asks its host for — `EntityKinds`,
  /// `RendererSteps`, `WorldFields` — made fresh for each loop, for
  /// [backend] (null for none).
  final List<PluginRegistry> Function(String? backend)? registries;

  /// The application's own part of the loop: the phases and systems that
  /// step the world the plugin acts on, and that world — in `loop.world`, or
  /// a `SnapshotPart` added to `loop.snapshots` for state kept elsewhere.
  /// Called once on every loop the suite builds, after the plugins are
  /// installed and before a step runs; every loop after the first is then
  /// put back to the state the first began from, through its snapshots.
  final void Function(EngineLoop loop)? setUp;

  /// The plugins the one under test depends on, made fresh for each loop.
  final List<Flutter3dPlugin> Function()? dependencies;

  /// How many steps the determinism, switching and budget runs take.
  final int steps;
}

/// What one check found, on one backend where the check is per backend.
final class PluginCheckOutcome {
  const PluginCheckOutcome({
    required this.check,
    required this.passed,
    required this.says,
    this.backend,
    this.declined = false,
  });

  /// One of `pluginCheckNames`.
  final String check;

  /// The backend this outcome is about, for the backends check; null for
  /// the others and for the run with no backend at all.
  final String? backend;

  /// Whether the plugin did what the check asks.
  final bool passed;

  /// Whether the check could not be asked — no budget declared, assertions
  /// off, no world given. Never green: a declined check is reported as
  /// skipped, with [says] as the reason, and keeps the badge away.
  final bool declined;

  /// The sentence a person reads beside the check's name.
  final String says;

  @override
  String toString() =>
      '$check${backend == null ? '' : ' on $backend'}: '
      '${declined ? 'declined' : (passed ? 'passed' : 'FAILED')} — $says';
}

/// What a plugin promises to cost, read from its manifest's `budget`.
///
/// ```dart
/// PluginManifest(
///   id: 'wind',
///   apiVersion: PluginApiVersion(1, 0),
///   extra: {'budget': {'stepMicroseconds': 200, 'eventsPerStep': 8}},
/// )
/// ```
///
/// **In the manifest's open keys**, because the manifest keeps what it does
/// not know and a later minor of the plugin API may give the budget a field
/// of its own without moving where a plugin wrote it.
final class PluginBudget {
  const PluginBudget({this.stepMicroseconds, this.eventsPerStep});

  /// The most the plugin may add to one step, in microseconds, measured as
  /// the median over several batches on the machine running the suite.
  final int? stepMicroseconds;

  /// The most events the plugin's step may publish in any one step.
  final int? eventsPerStep;

  /// The budget [manifest] declares, or null when it declares none or one
  /// that does not read — the manifest check says which, in a sentence.
  static PluginBudget? of(PluginManifest manifest) {
    if (budgetProblemOf(manifest) != null) return null;
    final raw = manifest.extra['budget'];
    if (raw is! Map) return null;
    return PluginBudget(
      stepMicroseconds: raw['stepMicroseconds'] as int?,
      eventsPerStep: raw['eventsPerStep'] as int?,
    );
  }
}

/// Why [manifest]'s budget does not read, or null when it does or there is
/// none. Shared by [PluginBudget.of] and the manifest check, so the two
/// cannot disagree about what a well-formed budget is.
String? budgetProblemOf(PluginManifest manifest) {
  if (!manifest.extra.containsKey('budget')) return null;
  final raw = manifest.extra['budget'];
  if (raw is! Map) {
    return 'its "budget" is not a map of stepMicroseconds and eventsPerStep';
  }
  for (final key in raw.keys) {
    if (key != 'stepMicroseconds' && key != 'eventsPerStep') {
      return 'its budget names "$key", and a budget is stepMicroseconds and '
          'eventsPerStep';
    }
    final value = raw[key];
    if (value is! int || value < 0) {
      return 'its budget\'s "$key" is $value, and a budget is a whole number '
          'of nought or more';
    }
  }
  if (raw.isEmpty) return 'its budget is empty, which promises nothing';
  return null;
}
