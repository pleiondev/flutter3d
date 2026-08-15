import 'track.dart';

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
  finished,
}

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

  /// A lap was completed. The lap time it was completed in is [lastLap].
  bool lapCompletedThisStep = false;

  /// That lap was the quickest so far.
  bool bestLapThisStep = false;

  /// A checkpoint was passed.
  bool checkpointThisStep = false;

  /// The car started going the wrong way, as opposed to still going it.
  bool wrongWayStartedThisStep = false;

  /// The car left the racing surface.
  bool leftRoadThisStep = false;

  /// The car was put back on the track.
  bool respawnedThisStep = false;

  /// This car crossed the line for the last time.
  bool finishedThisStep = false;

  /// How long the lap just completed took.
  double lastLap = 0.0;

  void clearStepFlags() {
    lapCompletedThisStep = false;
    bestLapThisStep = false;
    checkpointThisStep = false;
    wrongWayStartedThisStep = false;
    leftRoadThisStep = false;
    respawnedThisStep = false;
    finishedThisStep = false;
  }
}

/// The race itself: the lights, the laps, and who is in front.
///
/// Separate from the simulation that fills it in, so that a heads-up display, a
/// commentator or a test can be handed the state of a race without being handed
/// the machinery that runs one.
final class RaceState {
  RaceState({
    required this.mode,
    required this.track,
    required int racers,
    this.laps = 3,
    this.countdownSeconds = 3.0,
  })  : progress = List<RacerProgress>.generate(
          racers,
          (int index) => RacerProgress(index: index),
          growable: false,
        ),
        phase = mode == RaceMode.race ? RacePhase.countdown : RacePhase.running,
        countdown = mode == RaceMode.race ? countdownSeconds : 0.0;

  final RaceMode mode;
  final TrackSpline track;

  /// How many laps a race is. Ignored in the modes that do not end.
  final int laps;

  final double countdownSeconds;

  /// One per car, in the order the cars were given. Nought is the player.
  final List<RacerProgress> progress;

  RacePhase phase;

  /// Seconds left on the lights.
  double countdown;

  /// The whole race clock, in simulated seconds.
  double elapsed = 0.0;

  /// True on the step the countdown moved from one whole second to the next,
  /// which is when a light goes out and a beep plays.
  bool countdownTickThisStep = false;

  /// True on the step the lights went out.
  bool startedThisStep = false;

  /// Where this car is running, counting from one.
  ///
  /// Ranked on laps and metres together, so a car half a lap ahead is ahead
  /// however the track loops back past itself. Cars that have finished keep the
  /// order they finished in, ahead of everyone still going — otherwise a winner
  /// slowing down on the line would be overtaken in the standings by somebody a
  /// lap down.
  int positionOf(int racer) {
    final mine = progress[racer];
    var ahead = 0;
    for (final other in progress) {
      if (identical(other, mine)) continue;
      if (_isAhead(other, mine)) ahead += 1;
    }
    return ahead + 1;
  }

  bool _isAhead(RacerProgress other, RacerProgress mine) {
    if (other.finished && mine.finished) {
      return other.finishedAt! < mine.finishedAt!;
    }
    if (other.finished != mine.finished) return other.finished;
    return other.progressAlong(track.length) > mine.progressAlong(track.length);
  }

  /// The quickest lap anybody has done, or null before there is one.
  double? get bestLap {
    double? best;
    for (final racer in progress) {
      final lap = racer.bestLap;
      if (lap != null && (best == null || lap < best)) best = lap;
    }
    return best;
  }

  void clearStepFlags() {
    countdownTickThisStep = false;
    startedThisStep = false;
    for (final racer in progress) {
      racer.clearStepFlags();
    }
  }
}
