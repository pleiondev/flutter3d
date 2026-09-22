/// `net-00`: what a rollback costs on the game that ships, not on a toy.
///
///     flutter test test/rollback_cost_test.dart
///
/// See `apps/flutter3d_demo_dungeon/test/rollback_cost_test.dart` for why
/// this prints a number rather than asserting a fixed threshold.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_demo_racing/src/staging.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const double _dt = 1.0 / 60.0;

const GameAction _throttle = GameAction('throttle');
const GameAction _brake = GameAction('brake');
const GameAction _left = GameAction('steerLeft');
const GameAction _right = GameAction('steerRight');
const GameAction _handbrake = GameAction('handbrake');

TrackDocument _shipped([String circuit = 'ring']) => TrackDocument.fromJson(
  jsonDecode(File('assets/tracks/$circuit.json').readAsStringSync())
      as Map<String, Object?>,
);

({RacingSimulation sim, InputState input}) _stage() {
  final document = _shipped();
  final world = CollisionWorld();
  document.level?.addTo(world);
  final input = InputState();
  final staged = stage(document, world, cars: 1, laps: 1);
  return (sim: staged.sim, input: input);
}

/// The same four lines as `main.dart`'s private `_readDriver`.
void _readDriver(RacingSimulation sim, InputState input) {
  final driven = sim.inputs[0];
  driven
    ..throttle = input.value(_throttle)
    ..brake = input.value(_brake)
    ..handbrake = input.held(_handbrake)
    ..steer = input.value(_right) - input.value(_left);
}

void _play(InputState input, int step) {
  input.setActionValue(_throttle, step % 40 < 30 ? 1.0 : 0.0);
  input.setActionValue(
    _brake,
    (step % 200 >= 150 && step % 200 < 170) ? 0.6 : 0.0,
  );
  final steeringRight = step % 80 < 40;
  input.setActionValue(_right, steeringRight ? 0.4 : 0.0);
  input.setActionValue(_left, steeringRight ? 0.0 : 0.4);
  if (step == 300) input.press(_handbrake);
  if (step == 305) input.release(_handbrake);
}

/// A step's worth of drive: the driver reads the current input, the vehicle
/// steps, then the input's one-shot transitions clear — the same order
/// `main.dart` and `demo_test.dart` both use.
void _step(({RacingSimulation sim, InputState input}) live) {
  _readDriver(live.sim, live.input);
  live.sim.step(_dt);
  live.input.endStep();
}

void main() {
  test('restore + k steps of the shipped ring, k = 1..10', () {
    final live = _stage();
    for (var step = 0; step < 300; step++) {
      _play(live.input, step);
      _step(live);
    }
    final snapshot = live.sim.save();

    live.sim.restore(snapshot);
    for (var i = 0; i < 10; i++) {
      _step(live);
    }

    final results = <int, double>{};
    for (var k = 1; k <= 10; k++) {
      const trials = 20;
      final watch = Stopwatch();
      for (var trial = 0; trial < trials; trial++) {
        live.sim.restore(snapshot);
        watch.start();
        for (var step = 0; step < k; step++) {
          _step(live);
        }
        watch.stop();
      }
      results[k] = watch.elapsedMicroseconds / trials / 1000.0;
    }

    // ignore: avoid_print
    print(
      'net-00 racing (ring): ${[for (final k in results.keys) 'k=$k ${results[k]!.toStringAsFixed(4)}ms'].join(', ')}',
    );

    expect(results[8], isNotNull);
    expect(results[10]!, greaterThanOrEqualTo(results[1]!));
  });
}
