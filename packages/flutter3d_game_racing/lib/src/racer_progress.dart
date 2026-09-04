import 'package:flutter3d_game/flutter3d_game.dart';

/// How far round one car has got.
///
/// Everything here is derived from where the car is, once per step, and none of
/// it is stored on the car: a car does not know what a lap is, and the whole
/// point of [RaceMode.freeRoam] is that it still drives when nothing is
/// counting.
final class RacerProgress {
  RacerProgress({required this.index});

  /// Which car this belongs to. Nought is the player.
  final int index;

  /// How far along the track, in metres. Wraps at the finish line.
  double s = 0.0;

  /// How many complete laps, counted only when every checkpoint was passed on
  /// the way round.
  int lap = 0;

  /// The checkpoint this car is driving towards.
  int nextCheckpoint = 0;

  /// True while the car has been going the wrong way long enough to mean it.
  bool wrongWay = false;

  /// True while the car is off the racing surface.
  bool offRoad = false;

  /// How far to the side of the centre line the car is, in metres.
  double lateral = 0.0;

  /// How long this lap has taken so far, in simulated seconds.
  double lapTime = 0.0;

  /// The quickest completed lap, or null before there is one.
  double? bestLap;

  /// How long the car has been racing.
  double totalTime = 0.0;

  /// The time this car finished at, or null while it is still going.
  double? finishedAt;

  bool get finished => finishedAt != null;

  /// Laps and metres together: the number cars are ranked by.
  double progressAlong(double lapLength) => lap * lapLength + s;

  // --- what happened on this step, for a sound or a caption ------------------

  /// How long the lap just completed took.
  double lastLap = 0.0;

  /// What this car has done so far.
  ///
  /// **The step flags are deliberately not here.** They say what happened on
  /// one step, and they are cleared at the top of the next one — a save that
  /// carried them would make a restored race announce a lap, a checkpoint and a
  /// respawn that happened before it was written down. What is saved is the
  /// state; the edges belong to the step that produced them.
  Map<String, Object?> save() => <String, Object?>{
    's': s,
    'lap': lap,
    'nextCheckpoint': nextCheckpoint,
    'wrongWay': wrongWay,
    'offRoad': offRoad,
    'lateral': lateral,
    'lapTime': lapTime,
    if (bestLap != null) 'bestLap': bestLap,
    'totalTime': totalTime,
    if (finishedAt != null) 'finishedAt': finishedAt,
    'lastLap': lastLap,
  };

  void restore(Map<String, Object?> from) {
    s = from.number('s');
    lap = from.integer('lap');
    nextCheckpoint = from.integer('nextCheckpoint');
    wrongWay = from.flag('wrongWay');
    offRoad = from.flag('offRoad');
    lateral = from.number('lateral');
    lapTime = from.number('lapTime');
    // Absent means never set, which is not the same as nought: a car with a
    // best lap of zero has driven a perfect lap in no time at all, and every
    // ranking that reads it puts them first for ever.
    bestLap = from['bestLap'] is num ? from.number('bestLap') : null;
    totalTime = from.number('totalTime');
    finishedAt = from['finishedAt'] is num ? from.number('finishedAt') : null;
    lastLap = from.number('lastLap');
    clearStepFlags();
  }

  void clearStepFlags() {}
}
