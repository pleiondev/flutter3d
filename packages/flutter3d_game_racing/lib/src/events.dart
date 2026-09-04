/// What a step of this game did, for a game that wants to hear about it.
///
/// Drained from `RacingSimulation.events` after each step. See [GameEvent] for
/// why this is a drained buffer rather than a stream, and for why nothing here
/// names a sound: these say what happened, and what to do about it is the
/// game's.
///
/// **Every one of these carries the racer it happened to**, which the flags
/// they replace did not have to: a flag lived on one [RacerProgress], so a
/// caller found out who by knowing whose flag it had just read. That works
/// while a caller walks the field in a loop and stops working the moment
/// anything wants the field's moments in the order they happened — two cars
/// crossing the line a step apart, a lap record set behind an overtake.
///
/// A game that adds a mechanic adds its own event beside these — [GameEvent] is
/// open, and nothing here dispatches on the type.
library;

import 'package:flutter3d_game/flutter3d_game.dart';

import 'racer_progress.dart';

/// Something one car did.
///
/// The base of everything below, so that a game listening for "anything that
/// happened to the player" filters on one type and reads one field rather than
/// asking each event separately who it belonged to.
abstract base class RacerEvent extends GameEvent {
  const RacerEvent(this.racer);

  /// Whose it was. Nought is the player; see [RacerProgress.index].
  final RacerProgress racer;

  /// Shorthand for the common question, and the reason this base exists.
  bool get isPlayer => racer.index == 0;
}

/// A lap was completed.
///
/// [RacerProgress.lastLap] is the time it took, and [BestLapSet] follows this
/// one on the step the lap was also the quickest — two events rather than a
/// flag on one, because a game that shows a lap time and a game that celebrates
/// a record are doing different things and one of them is optional.
final class LapCompleted extends RacerEvent {
  const LapCompleted(super.racer);

  @override
  String get name => 'lap completed (car ${racer.index})';
}

/// The lap just completed was this car's quickest.
final class BestLapSet extends RacerEvent {
  const BestLapSet(super.racer);

  @override
  String get name => 'best lap (car ${racer.index})';
}

/// A checkpoint was passed.
final class CheckpointPassed extends RacerEvent {
  const CheckpointPassed(super.racer);

  @override
  String get name => 'checkpoint (car ${racer.index})';
}

/// The car started going the wrong way round.
///
/// Once, when it starts — not on every step it keeps doing it, which is what
/// reading [RacerProgress.wrongWay] gives.
final class WentWrongWay extends RacerEvent {
  const WentWrongWay(super.racer);

  @override
  String get name => 'wrong way (car ${racer.index})';
}

/// The car left the road.
///
/// Once, on the step it crossed the edge. A car that is already off the road
/// and stays off it is not leaving it again.
final class LeftTheRoad extends RacerEvent {
  const LeftTheRoad(super.racer);

  @override
  String get name => 'left the road (car ${racer.index})';
}

/// The car was put back on the road.
final class Respawned extends RacerEvent {
  const Respawned(super.racer);

  @override
  String get name => 'respawned (car ${racer.index})';
}

/// The car crossed the line for the last time.
final class RacerFinished extends RacerEvent {
  const RacerFinished(super.racer);

  @override
  String get name => 'finished (car ${racer.index})';
}

/// The starting light changed.
///
/// Belongs to the race rather than to a car, which is why it is not a
/// [RacerEvent].
final class CountdownTicked extends GameEvent {
  const CountdownTicked(this.remaining);

  /// How many lights are left, counting down to zero.
  final int remaining;

  @override
  String get name => 'countdown ($remaining)';
}

/// The lights went out and the race is running.
final class RaceStarted extends GameEvent {
  const RaceStarted();

  @override
  String get name => 'race started';
}

/// The race is over for everybody.
final class RaceFinished extends GameEvent {
  const RaceFinished();

  @override
  String get name => 'race finished';
}

/// A sector was finished.
///
/// One per stretch between checkpoints, plus one for the run from the last
/// checkpoint to the line — so a circuit with three checkpoints reports four
/// of these a lap.
///
/// **Carries the comparison as well as the time**, because a split a caller
/// has to compute is a split every caller computes differently: against the
/// lap so far, against the session, against the record. [delta] is against
/// this driver's own best for this sector, which is the one a driver is
/// actually chasing.
final class SectorCompleted extends RacerEvent {
  const SectorCompleted(super.racer, this.sector, this.time, this.delta);

  /// Which sector, counting from nought at the line.
  final int sector;

  /// How long it took, in simulated seconds.
  final double time;

  /// How much slower than this driver's best for this sector, or null when
  /// there was no best to compare against — which is every sector of a first
  /// lap. Negative is quicker, and quicker is what has just become the best.
  final double? delta;

  @override
  String get name => 'sector $sector in $time (car ${racer.index})';
}

/// A slide ended, and here is what it was worth.
///
/// **One event per slide rather than one a step**, because what a driver is
/// doing is one slide and not sixty a second: a score arriving in fragments
/// cannot say "that one was worth four hundred", which is the only thing
/// anybody wants to hear.
final class DriftScored extends RacerEvent {
  const DriftScored(super.racer, this.score, this.seconds);

  /// What it was worth. Grows with how far sideways and how fast.
  final double score;

  /// How long it was held.
  final double seconds;

  @override
  String get name => 'drift worth $score over $seconds (car ${racer.index})';
}
