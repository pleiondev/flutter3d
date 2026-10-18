import 'package:flutter3d_sim/flutter3d_sim.dart';

/// What a game is doing, as far as a screen is concerned.
///
/// Named `RunStatus` and not `RunState`, which a genre package may use for
/// its own enum: an application importing both never has to hide one.
///
/// **Open, and a screen draws something for every status.** Loading,
/// playing and failed are the three today; a fourth (paused for a call,
/// say) can arrive in a minor release, so a `switch` over a status ends with
/// a wildcard that draws a neutral frame rather than a black one. How a run
/// is going *inside* play is [RunOutcome].
abstract final class RunStatus<L> {
  const RunStatus();
}

/// Before the first level, and between one and the next.
final class RunLoading<L> extends RunStatus<L> {
  /// Loading [asset], or the first load when it is null.
  const RunLoading({this.asset});

  /// Which one is coming, when that is known. Null on the very first load,
  /// before anything has been asked for.
  final String? asset;
}

/// A level is up. [outcome] is the simulation's own answer, republished so a
/// screen can watch one thing.
final class RunPlaying<L> extends RunStatus<L> {
  /// [level], read from [asset], with the simulation's [outcome] so far.
  const RunPlaying(this.asset, this.level, {this.outcome = RunOutcome.playing});

  /// Which document this is. Kept because a save is a level and a snapshot
  /// together, and a snapshot restored into the wrong level is worse than no
  /// save at all.
  final String asset;

  /// Whatever the game got back from loading it: a scene, a simulation, the
  /// visuals. This class never looks inside.
  final L level;

  /// Whether the run is still going, lost or won: [RunOutcome.playing]
  /// until the simulation says otherwise.
  final RunOutcome outcome;
}

/// Nothing is up, and this is why.
///
/// **A level that will not read used to be a black screen for ever** in two of
/// the three games: the load caught its own throw and printed it, which is a
/// line in a console nobody playing the game can see.
final class RunFailed<L> extends RunStatus<L> {
  /// [asset] would not load, for [error].
  const RunFailed(this.asset, this.error);

  /// The document that would not load.
  final String asset;

  /// What the load threw, kept so a screen can say why rather than show a
  /// black frame.
  final Object error;
}
