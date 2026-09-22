/// The grid: who starts where, and by what rule.
///
///     flutter test test/staging_test.dart
///
/// `stage()`'s own tests, elsewhere, all stage a fresh field — car `i` in slot
/// `i`, which is every circuit's first running of a season and everything
/// `frame_test.dart`/`playthrough_test.dart` ever needed. This file is the
/// half those never touch: a car starting somewhere other than its own index,
/// and the rule — pole to the winner of the circuit before — that decides
/// where.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_demo_racing/src/staging.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

TrackDocument _shipped([String circuit = 'ring']) => TrackDocument.fromJson(
  jsonDecode(File('assets/tracks/$circuit.json').readAsStringSync())
      as Map<String, Object?>,
);

void main() {
  group('stage', () {
    // Neither test below calls `TrackSpline.startSlot` itself — `stage()` is
    // the only caller a shipped game has, and a harness with its own opinion
    // of where a slot sits would agree with a bug there rather than catch it
    // (`the structure rule 'no test builds its own world'`). What a slot
    // actually is comes only from `stage()`'s own default assembly, car `i`
    // in slot `i` — the shape every other test in this file already trusts.
    Staged identity(int cars) {
      final world = CollisionWorld();
      final document = _shipped();
      document.level?.addTo(world);
      return stage(document, world, cars: cars);
    }

    ({double x, double z}) positionOf(SphereVehicle car) =>
        (x: car.position.x, z: car.position.z);

    test('with no grid order, car i starts in slot i, as it always did', () {
      final slots = identity(3);

      final world = CollisionWorld();
      final document = _shipped();
      document.level?.addTo(world);
      final named = stage(document, world, cars: 3, gridOrder: <int>[0, 1, 2]);

      for (var i = 0; i < 3; i++) {
        expect(positionOf(named.cars[i]), positionOf(slots.cars[i]));
      }
    });

    test('with a grid order, a car starts in the slot named for it', () {
      final slots = identity(3);

      // Slot 0 (pole) goes to car 2; slot 1 to car 0; slot 2 to car 1.
      final world = CollisionWorld();
      final document = _shipped();
      document.level?.addTo(world);
      final named = stage(document, world, cars: 3, gridOrder: <int>[2, 0, 1]);

      expect(
        positionOf(named.cars[2]),
        positionOf(slots.cars[0]),
        reason: 'car 2 was named for pole (slot 0) and should be on it',
      );
      expect(positionOf(named.cars[0]), positionOf(slots.cars[1]));
      expect(positionOf(named.cars[1]), positionOf(slots.cars[2]));
    });
  });

  group('gridOrderFrom', () {
    RaceState raceOf(List<double?> finishedAt, {List<int>? laps}) {
      final race = RaceState(
        mode: RaceMode.race,
        track: _shipped().track,
        racers: finishedAt.length,
      );
      for (var i = 0; i < finishedAt.length; i++) {
        race.progress[i]
          ..lap = laps == null ? 0 : laps[i]
          ..finishedAt = finishedAt[i];
      }
      return race;
    }

    test('puts the winner on pole and the rest in the order they crossed', () {
      // Car 1 first, then car 2, then car 0.
      final race = raceOf(<double?>[30.0, 12.0, 18.0]);

      expect(gridOrderFrom(race), <int>[1, 2, 0]);
    });

    test('the one who crossed the line outranks the rivals still racing', () {
      // `_finishedHere` fires the moment the *player* crosses the line —
      // the rivals are almost never done at that exact step. Car 0 has
      // finished; cars 1 and 2 have not, and rank behind it regardless of
      // where they are on the track — `RaceState.positionOf`'s own doc
      // comment gives the reason: a finished car keeps the place it
      // finished in rather than being overtaken by one still going.
      // Between the two still racing, the one further along outranks the
      // other, the same way the HUD's own position number reads them.
      final race = raceOf(<double?>[9.0, null, null], laps: <int>[3, 3, 3]);
      race.progress[1].s = 50.0;
      race.progress[2].s = 900.0;

      expect(gridOrderFrom(race), <int>[0, 2, 1]);
    });

    test('a field that finished in grid order stays in grid order', () {
      final race = raceOf(<double?>[10.0, 20.0, 30.0, 40.0]);

      expect(gridOrderFrom(race), <int>[0, 1, 2, 3]);
    });
  });
}
