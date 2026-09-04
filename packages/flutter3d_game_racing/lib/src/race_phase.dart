import 'package:flutter3d_game/flutter3d_game.dart';

/// What the cars are doing here.
///
/// **A value class rather than an enum, carrying what the simulation asks of
/// it.** The three below were compared with `==` in four places — does it start
/// behind lights, does it count a lap, does it end after so many — so the mode
/// was already a label with three answers behind it rather than a case in a
/// switch. Written this way a game adds elimination, or a drift event, or a
/// pursuit, by answering the same three questions; as an enum it could not,
/// and adding a value broke every `switch` a published game had written.
///
/// The three questions are the whole contract. A mode that wants something
/// none of them can express — points for overtaking, a car removed each lap —
/// is a rule the game writes over this, in a step system; see `StepSystems`.
final class RaceMode {
  const RaceMode(
    this.name, {
    required this.startsBehindLights,
    required this.countsProgress,
    required this.endsAfterLaps,
  });

  /// What it is called, in a save and on a menu. Identity: two modes with the
  /// same name are the same mode.
  final String name;

  /// Whether the race begins on a grid with a countdown, or simply running.
  final bool startsBehindLights;

  /// Whether laps, checkpoints and positions are counted at all.
  ///
  /// False means the cars drive and nothing is watching, which is what a mode
  /// for finding out how a car feels wants: the clock still runs, so a session
  /// has a length, but nothing is a lap.
  final bool countsProgress;

  /// Whether reaching the lap count finishes a car's race.
  final bool endsAfterLaps;

  /// No timing, no order, no lights. For finding out what a car feels like,
  /// which is most of what a racing game is developed against.
  static const RaceMode freeRoam = RaceMode(
    'freeRoam',
    startsBehindLights: false,
    countsProgress: false,
    endsAfterLaps: false,
  );

  /// One car against the clock. The mode every racing game has, and the one
  /// that needs least: a track, a car and a lap time.
  static const RaceMode timeTrial = RaceMode(
    'timeTrial',
    startsBehindLights: false,
    countsProgress: true,
    endsAfterLaps: false,
  );

  /// Cars against each other, from a grid, over a set number of laps.
  static const RaceMode race = RaceMode(
    'race',
    startsBehindLights: true,
    countsProgress: true,
    endsAfterLaps: true,
  );

  @override
  bool operator ==(Object other) => other is RaceMode && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'RaceMode($name)';
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
