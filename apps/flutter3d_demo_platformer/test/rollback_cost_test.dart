/// `net-00`: what a rollback costs on the game that ships, not on a toy.
///
///     flutter test test/rollback_cost_test.dart
///
/// See `apps/flutter3d_demo_dungeon/test/rollback_cost_test.dart` for why
/// this prints a number rather than asserting a fixed threshold.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_demo_platformer/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

const double _dt = 1.0 / 60.0;

Level _shipped() => Level.fromJson(
  jsonDecode(File('assets/levels/ascent.json').readAsStringSync())
      as Map<String, Object?>,
);

({PlatformerSimulation sim, InputState input}) _stage() {
  final level = _shipped();
  final world = CollisionWorld();
  level.addTo(world);
  final input = InputState();
  final staged = stage(
    level,
    world,
    input: input,
    registry: platformerRegistry(),
  );
  world.update();
  return (sim: staged.sim, input: input);
}

void _play(InputState input, int step) {
  if (step % 30 < 22) {
    input.press(GameAction.moveForward);
  } else {
    input.release(GameAction.moveForward);
  }
  if (step % 60 == 0) input.press(GameAction.jump);
  if (step % 60 == 3) input.release(GameAction.jump);
  if (step % 90 == 45) input.press(PlatformerActions.dropThrough);
  if (step % 90 == 46) input.release(PlatformerActions.dropThrough);
}

void main() {
  test('restore + k steps of the shipped ascent, k = 1..10', () {
    final live = _stage();
    for (var step = 0; step < 300; step++) {
      _play(live.input, step);
      live.sim.step(_dt);
      live.input.endStep();
    }
    final snapshot = live.sim.save();

    live.sim.restore(snapshot);
    for (var i = 0; i < 10; i++) {
      live.sim.step(_dt);
      live.input.endStep();
    }

    final results = <int, double>{};
    for (var k = 1; k <= 10; k++) {
      const trials = 20;
      final watch = Stopwatch();
      for (var trial = 0; trial < trials; trial++) {
        live.sim.restore(snapshot);
        watch.start();
        for (var step = 0; step < k; step++) {
          live.sim.step(_dt);
          live.input.endStep();
        }
        watch.stop();
      }
      results[k] = watch.elapsedMicroseconds / trials / 1000.0;
    }

    // ignore: avoid_print
    print(
      'net-00 platformer (ascent): ${[for (final k in results.keys) 'k=$k ${results[k]!.toStringAsFixed(4)}ms'].join(', ')}',
    );

    expect(results[8], isNotNull);
    expect(results[10]!, greaterThanOrEqualTo(results[1]!));
  });
}
