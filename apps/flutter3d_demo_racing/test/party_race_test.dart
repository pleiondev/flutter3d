/// A race of four machines, each driving its own car, kept in step by the
/// party's rollback over a late and lossy wire.
///
///     flutter test test/party_race_test.dart
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flame_multiplayer/flame_multiplayer.dart';
import 'package:flutter3d_demo_racing/src/party_race.dart';
import 'package:flutter3d_demo_racing/src/staging.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _throttle = GameAction('throttle');
const GameAction _left = GameAction('steerLeft');
const GameAction _right = GameAction('steerRight');

TrackDocument _ring() => TrackDocument.fromJson(
  jsonDecode(File('assets/tracks/ring.json').readAsStringSync())
      as Map<String, Object?>,
);

void _drive(InputState input, int step, int car) {
  final s = step + car * 17;
  input.setActionValue(_throttle, s % 40 < 30 ? 1.0 : 0.2);
  final right = s % 80 < 40;
  input.setActionValue(_right, right ? 0.3 + car * 0.1 : 0.0);
  input.setActionValue(_left, right ? 0.0 : 0.3);
}

void main() {
  test('four machines settle every step on the same race', () {
    const cars = 4;
    final party = LoopbackParty(cars, delaySteps: 3, lossRate: 0.05, seed: 2);
    final settled = List<Map<int, int>>.generate(cars, (_) => <int, int>{});
    final races = <({PartyRace race, InputState input})>[];
    for (var car = 0; car < cars; car++) {
      final document = _ring();
      final world = CollisionWorld();
      document.level?.addTo(world);
      final input = InputState();
      final staged = stage(document, world, cars: cars, laps: 1);
      races.add((
        race: PartyRace(
          sim: staged.sim,
          wire: party.wire(car),
          cars: cars,
          localInput: input,
          maxRollbackFrames: 24,
          onSettled: (step, after, _) =>
              settled[car][step] = StateDigest.of(after.toJson()),
        ),
        input: input,
      ));
    }
    for (var step = 0; step < 360; step++) {
      for (final (index, it) in races.indexed) {
        _drive(it.input, step, index);
        it.race.advance();
      }
      party.tick();
    }
    // Every machine heard every other, and drove its own car.
    for (final (index, it) in races.indexed) {
      expect(it.race.localCarIndex, index);
      expect(it.race.heard, <int>{0, 1, 2, 3}..remove(index));
      expect(it.race.session.droppedCorrections, 0);
    }
    // Mutation: a car whose frame is applied to the slot of another, or a
    // machine that ghosts its own car — the races part.
    final steps = settled[0].keys.toSet();
    expect(steps.length, greaterThan(300));
    for (var car = 1; car < cars; car++) {
      for (final step in steps.intersection(settled[car].keys.toSet())) {
        expect(
          settled[car][step],
          settled[0][step],
          reason: 'car $car, step $step',
        );
      }
    }
  });
}
