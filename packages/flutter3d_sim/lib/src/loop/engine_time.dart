import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// The rate a world is stepped at when nobody says otherwise, in steps per
/// second: what every recorded run, tape and golden here was made under.
///
/// **The loop's, beside [WorldTiming].** It was in `flutter3d_physics`'
/// standard world until 1.0.0-rc.1, because `WorldProperties` carried a step
/// rate too; what a world is made of (`flutter3d_matter`) is not how often it
/// is stepped, and only the loop reads this.
const double standardStepRate = 60.0;

/// How a world is stepped in time: its step rate.
///
/// **A property of the world, as gravity is.** A world stepped at 120 Hz is
/// a different world from the same one at 60 — a jump integrates to a
/// different height — so the rate is the world's to say and the loop's to
/// keep, not a number each game writes into its own clock. A level or a
/// world preset hands one of these to the `EngineLoop`; a change to it is a
/// change to the simulation and is journalled like one.
final class WorldTiming {
  const WorldTiming({this.stepRate = standardStepRate})
    : assert(stepRate > 0.0, 'a world steps at some rate');

  /// Steps per second of simulated time.
  final double stepRate;

  /// Seconds of simulated time one step covers: the `dt` every step system
  /// is handed.
  double get stepSeconds => 1.0 / stepRate;

  @override
  bool operator ==(Object other) =>
      other is WorldTiming && other.stepRate == stepRate;

  @override
  int get hashCode => stepRate.hashCode;

  @override
  String toString() => 'WorldTiming(${stepRate}Hz)';
}

/// What the loop does when a frame brings more time than it may step.
///
/// **Never silent.** The loop before `EngineLoop` dropped the backlog past
/// five steps and counted it in a number few callers read; a machine that
/// could not keep up then ran the game slowly and said nothing. Both policies here publish a
/// [TimeLost] for whatever they do not run, and the loop keeps the totals.
///
/// * [CatchUp.announce] runs at most [maxStepsPerFrame] steps, drops the
///   rest and announces it: today's behaviour, now heard.
/// * [CatchUp.within] carries up to [backlog] seconds of debt into the
///   following frames, so a hitch is made up for rather than lost, and
///   announces only what is past the cap. The spiral that loop warned of
///   cannot start, because the debt is bounded.
final class CatchUp {
  /// Runs at most [maxStepsPerFrame] steps a frame and announces the rest.
  const CatchUp.announce({this.maxStepsPerFrame = 5})
    : backlog = 0.0,
      assert(maxStepsPerFrame > 0);

  /// Runs at most [maxStepsPerFrame] steps a frame and carries up to
  /// [backlog] seconds of simulated time over to the next frames.
  const CatchUp.within({this.maxStepsPerFrame = 5, required this.backlog})
    : assert(maxStepsPerFrame > 0),
      assert(backlog >= 0.0);

  final int maxStepsPerFrame;

  /// Simulated seconds that may wait for a later frame. Nought announces
  /// everything a frame cannot run.
  final double backlog;

  @override
  String toString() => backlog == 0.0
      ? 'CatchUp.announce($maxStepsPerFrame a frame)'
      : 'CatchUp.within($maxStepsPerFrame a frame, ${backlog}s behind)';
}

/// Why simulated time was not run.
///
/// An open value class rather than an enum (ARCHITECTURE.md §13.1): a
/// later minor may find a third reason.
final class TimeLostReason {
  const TimeLostReason._(this.name);

  /// The frame took longer than the loop's longest frame — a dragged
  /// window, a breakpoint, a laptop lid — and the excess was never handed
  /// to the clock.
  static const TimeLostReason longFrame = TimeLostReason._('longFrame');

  /// The frame brought more steps than the catch-up policy allows.
  static const TimeLostReason overBudget = TimeLostReason._('overBudget');

  final String name;

  @override
  String toString() => name;
}

/// Simulated time the loop did not run, announced on the frame channel.
///
/// **On the frame channel, never the step channel.** How much time a
/// machine lost is a fact about the machine; the step channel is digested
/// and replayed, and a replay on a faster machine would lose nothing and
/// differ. What a game does about it — a "running slowly" notice, a pacing
/// report — is presentation.
final class TimeLost extends BusEvent {
  const TimeLost({
    required this.seconds,
    required this.steps,
    required this.reason,
  });

  /// Simulated seconds not run.
  final double seconds;

  /// Whole steps not run; nought for a long frame shorter than a step.
  final int steps;

  final TimeLostReason reason;

  @override
  String get name => 'time.lost';

  @override
  String toString() => 'time.lost: ${seconds}s (${reason.name})';
}
