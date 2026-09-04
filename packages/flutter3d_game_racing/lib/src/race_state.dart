import 'package:flutter3d_game/flutter3d_game.dart';

import 'race_phase.dart';
import 'racer_progress.dart';
import 'track.dart';

export 'race_phase.dart';
export 'racer_progress.dart';

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
  }) : progress = List<RacerProgress>.generate(
         racers,
         (int index) => RacerProgress(index: index),
         growable: false,
       ),
       phase = mode.startsBehindLights
           ? RacePhase.countdown
           : RacePhase.running,
       countdown = mode.startsBehindLights ? countdownSeconds : 0.0;

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

  /// The race itself, written down.
  ///
  /// **The mode, the track and the number of laps are not here**, and that is
  /// the same boundary `Snapshot` draws: a save restores into the level it was
  /// taken in. What a race *is* comes from the circuit that was loaded; what
  /// this carries is how far into it everybody has got.
  Map<String, Object?> save() => <String, Object?>{
    'phase': phase.name,
    'countdown': countdown,
    'elapsed': elapsed,
    'progress': <Map<String, Object?>>[
      for (final racer in progress) racer.save(),
    ],
  };

  /// Reads a race back into the field it was saved from.
  ///
  /// Cars that are not in this world are ignored, and cars this world has that
  /// the save did not are left where they are — the same leniency the rest of
  /// the snapshot machinery keeps, so that a save from a build with a smaller
  /// grid loads rather than refuses.
  void restore(Map<String, Object?> from) {
    phase = from.enumOf('phase', RacePhase.values, phase);
    countdown = from.number('countdown', countdown);
    elapsed = from.number('elapsed');
    final rows = from['progress'];
    if (rows is! List) return;
    for (var i = 0; i < progress.length && i < rows.length; i++) {
      final row = rows[i];
      if (row is Map) progress[i].restore(row.cast<String, Object?>());
    }
  }

  void clearStepFlags() {
    for (final racer in progress) {
      racer.clearStepFlags();
    }
  }
}
