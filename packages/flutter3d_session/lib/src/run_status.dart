import 'package:flutter3d_game/flutter3d_game.dart';

/// What a game is doing, as far as a screen is concerned.
///
/// Named `RunStatus` and not `RunState`, which is taken:
/// `flutter3d_game_platformer` exports an enum of that name, and an application that
/// imported both would have to hide one of them in every file.
sealed class RunStatus<L> {
  const RunStatus();
}

/// Before the first level, and between one and the next.
final class RunLoading<L> extends RunStatus<L> {
  const RunLoading({this.asset});

  /// Which one is coming, when that is known. Null on the very first load,
  /// before anything has been asked for.
  final String? asset;
}

/// A level is up. [outcome] is the simulation's own answer, republished so a
/// screen can watch one thing.
final class RunPlaying<L> extends RunStatus<L> {
  const RunPlaying(this.asset, this.level, {this.outcome = RunOutcome.playing});

  /// Which document this is. Kept because a save is a level and a snapshot
  /// together, and a snapshot restored into the wrong level is worse than no
  /// save at all.
  final String asset;

  /// Whatever the game got back from loading it: a scene, a simulation, the
  /// visuals. This class never looks inside.
  final L level;

  final RunOutcome outcome;
}

/// Nothing is up, and this is why.
///
/// **A level that will not read used to be a black screen for ever** in two of
/// the three games: the load caught its own throw and printed it, which is a
/// line in a console nobody playing the game can see.
final class RunFailed<L> extends RunStatus<L> {
  const RunFailed(this.asset, this.error);

  final String asset;
  final Object error;
}
