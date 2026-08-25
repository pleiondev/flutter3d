import 'package:flutter3d_game/flutter3d_game.dart';

/// What the cars are doing here.
enum RaceMode {
  /// No timing, no order, no lights. For finding out what a car feels like,
  /// which is most of what a racing game is developed against.
  freeRoam,

  /// One car against the clock. The mode every racing game has, and the one
  /// that needs least: a track, a car and a lap time.
  timeTrial,

  /// Cars against each other, from a grid, over a set number of laps.
  race,
}

/// Where a race has got to.
enum RacePhase {
  /// On the grid, lights on. Cars may rev and may not move.
  countdown,

  /// Being raced.
  running,

  /// Everyone who is going to finish has finished.
  finished;

  /// The same answer in the words every game shares.
  ///
  /// **A race has no [RunOutcome.lost]**, and that is the genre rather than an
  /// omission: everybody who starts crosses the line eventually, and coming
  /// last is a position rather than a defeat. A game that wants a time limit
  /// grows the losing phase then, and this switch is where it is noticed.
  RunOutcome get outcome => switch (this) {
        RacePhase.countdown || RacePhase.running => RunOutcome.playing,
        RacePhase.finished => RunOutcome.won,
      };
}
