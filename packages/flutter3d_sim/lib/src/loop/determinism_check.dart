import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// Steps each step twice from a snapshot, in a debug build, and names the
/// system that made the two runs differ.
///
/// **Decision 11 of `tasks/0.9-plugins.md`: a plugin that reads a clock, a
/// loose die or a hash map's order is found the day it is installed, not the
/// day a replay of somebody's run fails on a server.** A replay finds that a
/// run diverged, and at which step; it cannot say which of forty systems did
/// it. Running one step twice from the same state can, because everything a
/// system might read is the same both times except what it should not read.
///
/// ## How the system is found
///
/// The loop takes [capture] before the step, runs the step's phases and asks
/// [digest] after every system, puts the state back with [restore], and runs
/// the step again, asking after every system again. The first system whose
/// two digests differ is the one that diverged: everything before it agreed,
/// so it was handed the same state and gave two answers. That is the
/// bisection by system order done in one pass, at the cost of one digest per
/// system, which a debug build can pay. When every system agrees and the
/// step's events or the state after its step subscribers differ, the
/// divergence is in a subscriber, and the report says so.
///
/// ## What it costs and where it runs
///
/// **Only with assertions on.** `EngineLoop` arms it inside an `assert`, so a
/// release build never steps twice whatever it was handed: a debug run and a
/// test run pay for it, a player does not. [every] spaces the checks out for
/// a game whose digest is expensive.
///
/// The second run is the real one: the recorders, the tape and the frame
/// channel see the step once, as if nothing had been checked. A step
/// subscriber is handed the step's events twice, once per run, so one that
/// counts something outside the world it was given counts double while the
/// check is on; the world it changes is put back between the runs.
///
/// ## What the snapshot must cover
///
/// Left to the loop (no functions given), the check captures through the
/// loop's `Snapshots`: the world, a genre's run, and every part a plugin
/// added. **It refuses a loop whose snapshots hold nothing** — an empty world
/// and no other part — with a `StateError` at the first checked step: a check
/// of nothing agrees with itself whatever the systems do, and a green check
/// that checked nothing is worse than none. The rest of this section is for a
/// check given its own functions.
///
/// ## What the three functions must cover
///
/// Everything a step system writes: the application's world, and the state
/// of every plugin that keeps its own (an element's fields, a Wasm module's
/// memory). Whatever [capture] leaves out is state the second run starts
/// from where the first left it, and the check then reports a divergence
/// that is the snapshot's rather than the system's — the report names
/// [restore] first when the digest right after restoring is not the digest
/// the step began from.
final class DeterminismCheck {
  const DeterminismCheck({
    this.capture,
    this.restore,
    this.digest,
    this.every = 1,
    this.onDivergence,
  }) : assert(every > 0, 'a check every nought steps never runs');

  /// The state a step starts from, as anything [restore] takes back. Null,
  /// with [restore] and [digest], uses the loop's `snapshots` — the one path
  /// every snapshot takes, which covers the world and every plugin that
  /// registered a part. Pass functions only for state the loop does not hold.
  final Object? Function()? capture;

  /// Puts back what [capture] returned. Null uses the loop's `snapshots`.
  final void Function(Object? state)? restore;

  /// A number that differs when the state does. Null uses the loop's
  /// `snapshots`.
  final int Function()? digest;

  /// Checks every step whose number is a multiple of this.
  final int every;

  /// Told about each divergence. Null throws a [DeterminismError] once the
  /// step has finished, so the loop is left at a step boundary.
  final void Function(StepDivergence divergence)? onDivergence;
}

/// Where two runs of one step parted.
final class StepDivergence {
  const StepDivergence({
    required this.step,
    required this.reason,
    this.system,
    this.phase,
    this.owner,
  });

  /// The step that was run twice.
  final int step;

  /// The system whose two runs differed, or null when the systems agreed and
  /// something around them did not — see [reason].
  final String? system;

  /// The phase [system] runs in.
  final LoopPhase? phase;

  /// The plugin that added [system], by id; null for the application's own
  /// system, or when no system is named.
  final String? owner;

  /// What differed, as a sentence.
  final String reason;

  @override
  String toString() => 'step $step: $reason';
}

/// Thrown by `EngineLoop` when a [DeterminismCheck] with no `onDivergence`
/// finds two runs of a step that differ.
final class DeterminismError extends Error {
  DeterminismError(this.divergence);

  final StepDivergence divergence;

  @override
  String toString() => 'DeterminismError: $divergence';
}
