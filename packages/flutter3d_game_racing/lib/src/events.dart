/// What a step of this game did, for a game that wants to hear about it.
///
/// Published onto the engine's bus from inside the step that raised them
/// (`RacingSimulation.publishTo`, which `RacingPlugin` calls), each under the
/// name `RacingPlugin` declares it with and with its codec. See [GameEvent]
/// for why nothing here names a sound: these say what happened, and what to
/// do about it is the game's.
///
/// **A racer's event reads back as null.** Its codec writes the car's
/// [RacerProgress.index] and the event's own numbers, which is what a digest
/// and a trace need; the [RacerProgress] it carries is live race state, which
/// no plain value rebuilds.
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

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

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

  /// The name it is declared and published under.
  static const String eventName = 'racing.lapCompleted';

  /// Its codec: the car's index. Reads back as null; see the library doc.
  static final EventCodec<LapCompleted> codec = EventCodec<LapCompleted>.of(
    encode: (LapCompleted e) => e.racer.index,
    decode: (Object? data, int version) => null,
  );

  @override
  String get name => eventName;
}

/// The lap just completed was this car's quickest.
final class BestLapSet extends RacerEvent {
  const BestLapSet(super.racer);

  /// The name it is declared and published under.
  static const String eventName = 'racing.bestLapSet';

  /// Its codec: the car's index. Reads back as null; see the library doc.
  static final EventCodec<BestLapSet> codec = EventCodec<BestLapSet>.of(
    encode: (BestLapSet e) => e.racer.index,
    decode: (Object? data, int version) => null,
  );

  @override
  String get name => eventName;
}

/// A checkpoint was passed.
final class CheckpointPassed extends RacerEvent {
  const CheckpointPassed(super.racer);

  /// The name it is declared and published under.
  static const String eventName = 'racing.checkpointPassed';

  /// Its codec: the car's index. Reads back as null; see the library doc.
  static final EventCodec<CheckpointPassed> codec =
      EventCodec<CheckpointPassed>.of(
        encode: (CheckpointPassed e) => e.racer.index,
        decode: (Object? data, int version) => null,
      );

  @override
  String get name => eventName;
}

/// The car started going the wrong way round.
///
/// Once, when it starts — not on every step it keeps doing it, which is what
/// reading [RacerProgress.wrongWay] gives.
final class WentWrongWay extends RacerEvent {
  const WentWrongWay(super.racer);

  /// The name it is declared and published under.
  static const String eventName = 'racing.wentWrongWay';

  /// Its codec: the car's index. Reads back as null; see the library doc.
  static final EventCodec<WentWrongWay> codec = EventCodec<WentWrongWay>.of(
    encode: (WentWrongWay e) => e.racer.index,
    decode: (Object? data, int version) => null,
  );

  @override
  String get name => eventName;
}

/// The car left the road.
///
/// Once, on the step it crossed the edge. A car that is already off the road
/// and stays off it is not leaving it again.
final class LeftTheRoad extends RacerEvent {
  const LeftTheRoad(super.racer);

  /// The name it is declared and published under.
  static const String eventName = 'racing.leftTheRoad';

  /// Its codec: the car's index. Reads back as null; see the library doc.
  static final EventCodec<LeftTheRoad> codec = EventCodec<LeftTheRoad>.of(
    encode: (LeftTheRoad e) => e.racer.index,
    decode: (Object? data, int version) => null,
  );

  @override
  String get name => eventName;
}

/// The car was put back on the road.
final class Respawned extends RacerEvent {
  const Respawned(super.racer);

  /// The name it is declared and published under.
  static const String eventName = 'racing.respawned';

  /// Its codec: the car's index. Reads back as null; see the library doc.
  static final EventCodec<Respawned> codec = EventCodec<Respawned>.of(
    encode: (Respawned e) => e.racer.index,
    decode: (Object? data, int version) => null,
  );

  @override
  String get name => eventName;
}

/// The car crossed the line for the last time.
final class RacerFinished extends RacerEvent {
  const RacerFinished(super.racer);

  /// The name it is declared and published under.
  static const String eventName = 'racing.racerFinished';

  /// Its codec: the car's index. Reads back as null; see the library doc.
  static final EventCodec<RacerFinished> codec = EventCodec<RacerFinished>.of(
    encode: (RacerFinished e) => e.racer.index,
    decode: (Object? data, int version) => null,
  );

  @override
  String get name => eventName;
}

/// The starting light changed.
///
/// Belongs to the race rather than to a car, which is why it is not a
/// [RacerEvent].
final class CountdownTicked extends GameEvent {
  const CountdownTicked(this.remaining);

  /// The name it is declared and published under.
  static const String eventName = 'racing.countdownTicked';

  /// Its codec: the lights left. Reads back whole.
  static final EventCodec<CountdownTicked> codec =
      EventCodec<CountdownTicked>.of(
        encode: (CountdownTicked e) => e.remaining,
        decode: (Object? data, int version) =>
            data is int ? CountdownTicked(data) : null,
      );

  /// How many lights are left, counting down to zero.
  final int remaining;

  @override
  String get name => eventName;
}

/// The lights went out and the race is running.
final class RaceStarted extends GameEvent {
  const RaceStarted();

  /// The name it is declared and published under.
  static const String eventName = 'racing.raceStarted';

  /// Its codec: nothing to write. Reads back whole.
  static final EventCodec<RaceStarted> codec = EventCodec<RaceStarted>.of(
    encode: (RaceStarted e) => null,
    decode: (Object? data, int version) => const RaceStarted(),
  );

  @override
  String get name => eventName;
}

/// The race is over for everybody.
final class RaceFinished extends GameEvent {
  const RaceFinished();

  /// The name it is declared and published under.
  static const String eventName = 'racing.raceFinished';

  /// Its codec: nothing to write. Reads back whole.
  static final EventCodec<RaceFinished> codec = EventCodec<RaceFinished>.of(
    encode: (RaceFinished e) => null,
    decode: (Object? data, int version) => const RaceFinished(),
  );

  @override
  String get name => eventName;
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

  /// The name it is declared and published under.
  static const String eventName = 'racing.sectorCompleted';

  /// Its codec: the car's index, the sector, its time and the delta. Reads
  /// back as null; see the library doc.
  static final EventCodec<SectorCompleted> codec =
      EventCodec<SectorCompleted>.of(
        encode: (SectorCompleted e) => <Object?>[
          e.racer.index,
          e.sector,
          e.time,
          e.delta,
        ],
        decode: (Object? data, int version) => null,
      );

  /// Which sector, counting from nought at the line.
  final int sector;

  /// How long it took, in simulated seconds.
  final double time;

  /// How much slower than this driver's best for this sector, or null when
  /// there was no best to compare against — which is every sector of a first
  /// lap. Negative is quicker, and quicker is what has just become the best.
  /// In simulated seconds.
  final double? delta;

  @override
  String get name => eventName;
}

/// A slide ended, and here is what it was worth.
///
/// **One event per slide rather than one a step**, because what a driver is
/// doing is one slide and not sixty a second: a score arriving in fragments
/// cannot say "that one was worth four hundred", which is the only thing
/// anybody wants to hear.
final class DriftScored extends RacerEvent {
  const DriftScored(super.racer, this.score, this.seconds);

  /// The name it is declared and published under.
  static const String eventName = 'racing.driftScored';

  /// Its codec: the car's index, the score and how long the slide was held.
  /// Reads back as null; see the library doc.
  static final EventCodec<DriftScored> codec = EventCodec<DriftScored>.of(
    encode: (DriftScored e) => <Object?>[e.racer.index, e.score, e.seconds],
    decode: (Object? data, int version) => null,
  );

  /// What it was worth. Grows with how far sideways and how fast.
  /// In radian-metres, as `RacerProgress.driftScore` is.
  final double score;

  /// How long it was held.
  /// In simulated seconds.
  final double seconds;

  @override
  String get name => eventName;
}
