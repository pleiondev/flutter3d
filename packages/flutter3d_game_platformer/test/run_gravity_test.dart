/// The run's gravity is the world's, and the runner only reads it.
///
///     flutter test test/run_gravity_test.dart
///
/// A level that names its gravity names it for the runner too: it falls by
/// it, and its soles grip by it. A run in the platformer's world that names
/// none falls at 24 m/s², the value `MovementSettings` once defaulted to —
/// and with the very tuning object it was built with, so nothing about such
/// a run has changed.
library;

import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

Runner _runner({double? gravity, double y = 0.9}) {
  final world = CollisionWorld(properties: platformerWorld)
    ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(200.0, 1.0, 200.0));
  return Runner(
    body: CharacterController(world: world, position: Vector3(0.0, y, 0.0)),
    gravity: gravity,
  );
}

void step(Runner runner, InputState input) {
  input.beginStep();
  runner.step(_dt, input);
  input.endStep();
}

void main() {
  test('a run that names no gravity is the run it was', () {
    // Mutation: copy the tuning whatever its gravity in `Runner._inWorld` —
    // fails because the body then holds a tuning that is not the one it was
    // built with, and every identity the runner caches on goes with it.
    const tuning = MovementSettings();
    final world = CollisionWorld(properties: platformerWorld);
    final body = CharacterController(world: world, tuning: tuning);
    final runner = Runner(body: body);
    expect(runner.gravity, Runner.runGravity);
    expect(body.gravity, Runner.runGravity);
    expect(identical(body.tuning, tuning), isTrue);
  });

  test('on the Moon the runner falls by the Moon, and grips by it', () {
    // Mutation: leave the body's tuning at its own 24 m/s² — fails because
    // the runner then drops fifteen times as fast as its world. Mutation:
    // grip by `Runner.runGravity` rather than `gravity` — fails because the
    // soles then push as on the Earth-and-more, 16.3 m/s², and the runner is
    // at 2.72 m/s rather than 0.18 after ten steps.
    const moon = 1.62;
    final input = InputState();
    final falling = _runner(gravity: moon, y: 20.0);
    expect(falling.gravity, moon);
    expect(falling.body.tuning.gravity, moon);
    for (var i = 0; i < 30; i++) {
      step(falling, input);
    }
    // A velocity is single precision.
    expect(falling.body.velocity.y, closeTo(-moon * 30 * _dt, 1e-5));

    final standing = _runner(gravity: moon);
    for (var i = 0; i < 60; i++) {
      step(standing, input);
    }
    expect(standing.isGrounded, isTrue);
    input
      ..beginStep()
      ..press(GameAction.moveForward);
    standing.step(_dt, input);
    input.endStep();
    for (var i = 1; i < 10; i++) {
      step(standing, input);
    }
    // μ g: the soles push by the Moon's weight, 0.68 × 1.62 m/s².
    expect(
      standing.body.velocity.z,
      closeTo(const RunnerSettings().grip * moon * 10 * _dt, 1e-5),
    );
  });
}
