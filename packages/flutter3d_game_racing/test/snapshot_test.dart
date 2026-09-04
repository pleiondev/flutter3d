/// `RacingSimulation.save/restore`, which did not exist.
///
///     flutter test test/snapshot_test.dart
///
/// **This package could not be saved at all**, alone among the three genres:
/// the words `save` and `restore` did not appear in it. The other two have had
/// both since they were written, and a snapshot is the same object three times
/// over — a save file, a network packet and the input to a determinism test —
/// so one gap was three.
///
/// The rule the platformer's file states and this one keeps: **a field is only
/// under test at a moment when it is not zero.** Nothing here is snapshotted on
/// the grid; every state is driven into something interesting first.
library;

import 'dart:convert';

import 'package:flutter3d_game/flutter3d_game.dart'
    show Snapshot, SnapshotFormatException;
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'race_test.dart' show Race, driveRound;

const double _step = 1 / 60;

/// A save that has been through JSON, which is what a save file is.
///
/// Not the map straight back: `List<double>` comes back as `List<dynamic>` and
/// an `int` that was written as `2.0` comes back as a `double`, and a restore
/// that only ever sees its own output has never met either.
/// A snapshot out to JSON and back, which is what a save file does to it.
///
/// Through [Snapshot.toJson] and [Snapshot.fromJson] rather than around them,
/// so every test below also asserts that the version survives the trip. This
/// game's save was a bare map until now — no version, nothing to refuse a
/// document from a newer build with, and the wrong type for
/// `RunSession.snapshotOf` — so there was nothing here to round-trip.
Snapshot roundTrip(Snapshot saved) => Snapshot.fromJson(
  jsonDecode(jsonEncode(saved.toJson())) as Map<String, Object?>,
);

void main() {
  test('a race carries on from where it was saved', () {
    // **The whole claim, and the only one that needs the simulation.** Two
    // races, identical to the step: one driven straight through, one saved
    // halfway and restored into a fresh world. If anything the step reads is
    // missing from the save, the two come apart — and they come apart in a way
    // no field-by-field assertion would have predicted.
    final straight = Race(cars: 2, mode: RaceMode.race)
      ..simulation.race.phase = RacePhase.running;
    final halved = Race(cars: 2, mode: RaceMode.race)
      ..simulation.race.phase = RacePhase.running;

    driveRound(straight, seconds: 6.0);
    driveRound(halved, seconds: 6.0);

    final saved = roundTrip(halved.simulation.save());

    driveRound(straight, seconds: 4.0);

    final resumed = Race(cars: 2, mode: RaceMode.race)
      ..simulation.race.phase = RacePhase.running
      ..simulation.restore(saved);
    driveRound(resumed, seconds: 4.0);

    for (var i = 0; i < 2; i++) {
      expect(
        resumed.vehicles[i].position.x,
        closeTo(straight.vehicles[i].position.x, 1e-6),
        reason: 'car $i is somewhere else',
      );
      expect(
        resumed.vehicles[i].position.z,
        closeTo(straight.vehicles[i].position.z, 1e-6),
      );
      expect(
        resumed.race.progress[i].s,
        closeTo(straight.race.progress[i].s, 1e-6),
      );
      expect(resumed.race.progress[i].lap, straight.race.progress[i].lap);
    }
  });

  test('and the laps, the times and the best lap come back', () {
    // Driven far enough to complete one, because a best lap of null tests
    // nothing at all.
    final it = Race(mode: RaceMode.timeTrial);
    driveRound(it, seconds: 40.0);
    expect(
      it.player.lap,
      greaterThanOrEqualTo(1),
      reason: 'it never got round',
    );
    expect(it.player.bestLap, isNotNull);

    final saved = roundTrip(it.simulation.save());
    final loaded = Race(mode: RaceMode.timeTrial)..simulation.restore(saved);

    expect(loaded.player.lap, it.player.lap);
    expect(loaded.player.bestLap, closeTo(it.player.bestLap!, 1e-6));
    expect(loaded.player.totalTime, closeTo(it.player.totalTime, 1e-6));
    expect(loaded.race.elapsed, closeTo(it.race.elapsed, 1e-6));
  });

  test('and a lap that was never driven is not a lap driven in no time', () {
    // A best lap of null is not a best lap of nought: a car with a zero best
    // lap has driven a perfect lap instantly, and every ranking that reads it
    // puts them first for ever.
    final it = Race(mode: RaceMode.timeTrial);
    driveRound(it, seconds: 2.0);
    expect(it.player.bestLap, isNull);

    final loaded = Race(mode: RaceMode.timeTrial)
      ..simulation.restore(roundTrip(it.simulation.save()));

    expect(loaded.player.bestLap, isNull);
  });

  test('and the wheels are still turning', () {
    // The one field that is invisible and immediately wrong. The wheel speed is
    // the difference between the wheels and the road, which is what the tyre
    // model reads: restore a car at speed with wheels at rest and it spends the
    // next second locked up in a slide it never made.
    final it = Race();
    driveRound(it, seconds: 4.0, throttle: 1.0);
    expect(it.vehicles.single.speed, greaterThan(5.0));

    final loaded = Race()..simulation.restore(roundTrip(it.simulation.save()));

    // One step on each with the same input, which has to be said out loud:
    // what a driver is asking for is not part of the race's state — it is
    // filled in before every step, by keys or by an AI — so the saved race's
    // inputs still hold whatever `driveRound` left there and the restored
    // one's are fresh. Zero both, and the only difference left is the car.
    for (final race in <Race>[it, loaded]) {
      for (final input in race.simulation.inputs) {
        input.reset();
      }
    }
    it.simulation.step(_step);
    loaded.simulation.step(_step);

    expect(
      loaded.vehicles.single.speed,
      closeTo(it.vehicles.single.speed, 1e-6),
      reason: 'the restored car is not rolling the way the saved one was',
    );
    expect(
      loaded.vehicles.single.slipRatio.abs(),
      lessThan(0.5),
      reason: 'it came back locked up',
    );
  });

  test('and the countdown is where it was left', () {
    final it = Race(mode: RaceMode.race);
    it.simulation.step(_step);
    it.simulation.step(_step);
    expect(it.race.phase, RacePhase.countdown);

    final loaded = Race(mode: RaceMode.race)
      ..simulation.restore(roundTrip(it.simulation.save()));

    expect(loaded.race.phase, RacePhase.countdown);
    expect(loaded.race.countdown, closeTo(it.race.countdown, 1e-6));
  });

  test('and a restored car does not re-pass everything behind it', () {
    // **The invisible half of the save, and a mutation is what asked for this
    // test.** The simulation remembers where each car was last step, and that
    // is what "has it crossed the line" is measured against. Drop it and the
    // first step after a restore compares a car halfway round the lap against
    // the grid it started on — a jump of hundreds of metres that sweeps every
    // checkpoint between the two and counts them all, on one step.
    // Fifteen seconds puts this car about three quarters of the way round a
    // four-hundred-metre ring, with two checkpoints behind it — which is what
    // the claim needs: something behind the car that can be passed twice.
    final it = Race();
    driveRound(it, seconds: 15.0);
    expect(it.player.s, greaterThan(200.0), reason: 'it never left the grid');
    expect(
      it.player.nextCheckpoint,
      greaterThan(1),
      reason: 'nothing is behind it yet, so nothing can be re-passed',
    );

    final loaded = Race()..simulation.restore(roundTrip(it.simulation.save()));
    for (final input in loaded.simulation.inputs) {
      input.reset();
    }
    loaded.simulation.step(_step);

    expect(
      loaded.simulation.events.drain(),
      isEmpty,
      reason: 'a restored car reported passing what it had already passed',
    );
    expect(
      loaded.player.wrongWay,
      isFalse,
      reason: 'a car put back where it was is not driving backwards',
    );
  });

  test('and what the save does not carry is what the circuit says', () {
    // The boundary `Snapshot` draws, and this file's version of it: a save
    // restores into the level it was taken in. How many laps a race is, and
    // what shape the track is, come back from the circuit that was loaded —
    // which is what lets a save survive a track being re-generated.
    final it = Race(laps: 2);
    driveRound(it, seconds: 5.0);

    final loaded = Race(laps: 7)
      ..simulation.restore(roundTrip(it.simulation.save()));

    expect(loaded.race.laps, 7, reason: 'the save overwrote the circuit');
  });

  test('and a step flag is not something a save can announce', () {
    // Flags say what happened on one step and are cleared at the top of the
    // next. A save that carried them would have a restored race announcing a
    // checkpoint, a lap and a respawn that happened before it was written down
    // — a sound, a caption and a lap time, all for a second time.
    final it = Race();
    driveRound(it, seconds: 40.0);

    final saved = roundTrip(it.simulation.save());
    final loaded = Race()..simulation.restore(saved);

    expect(loaded.simulation.events.drain(), isEmpty);
  });

  test('a saved race says which format it is in', () {
    // This game's save was a bare `Map` — no version, no way to refuse a
    // document from a newer build, and the wrong type for
    // `RunSession.snapshotOf`, which every other genre answers. So the one
    // save mechanism the architecture describes had two users out of three,
    // and this was the one that would misread a future document field by
    // field rather than say so.
    //
    // Mutation: return the bare map again. This stops compiling, which is the
    // point of the type.
    final it = Race();
    driveRound(it, seconds: 2.0);

    expect(it.simulation.save().toJson()['version'], Snapshot.formatVersion);
    expect(
      () => Snapshot.fromJson(<String, Object?>{'version': 99}),
      throwsA(isA<SnapshotFormatException>()),
    );
  });
}
