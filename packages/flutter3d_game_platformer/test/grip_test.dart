/// The runner pushes along the floor no harder than its soles grip it.
///
///     flutter test test/grip_test.dart
///
/// `RunnerSettings.grip` is the soles' coefficient of friction, μ, and the most
/// the legs can add to the runner's speed is μ g (1 − lift) a second: Coulomb's
/// μ N over the mass, N the weight less what water about the legs bears.
/// These are its claims on a level floor, where nothing else takes speed off.
library;

import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

final class _Floor {
  _Floor({RunnerSettings tuning = const RunnerSettings()}) {
    world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(200.0, 1.0, 200.0));
    runner = Runner(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
      tuning: tuning,
    );
    // Stood still until the feet are on the floor.
    for (var i = 0; i < 20; i++) {
      step(forward: false);
    }
  }

  final CollisionWorld world = CollisionWorld(properties: platformerWorld);
  final InputState input = InputState();
  late final Runner runner;
  bool _forward = false;

  /// One step holding [forward], with [lift] written to the runner first, or
  /// nothing written when it is null.
  void step({bool forward = true, double? lift}) {
    input.beginStep();
    if (forward != _forward) {
      forward
          ? input.press(GameAction.moveForward)
          : input.release(GameAction.moveForward);
      _forward = forward;
    }
    if (lift != null) runner.lift = lift;
    runner.step(_dt, input);
    input.endStep();
  }

  double get speed => runner.body.velocity.z;
}

void main() {
  test(
    'on dry ground the legs get up to speed at μg, and to the same walk',
    () {
      // Under the run's gravity of 24 m/s² and a grip of 0.68, 16.32 m/s²:
      // ten steps from rest is 2.72 m/s, and the walk's 6 is still where it
      // stops.
      //
      // Mutation: drop the limit in `Runner._gripped` and the controller's 70
      // m/s² has the runner at the walk's 6 inside the ten steps. Mutation:
      // press with the Earth's 9.81 rather than the run's own gravity, and it
      // is 1.11.
      final floor = _Floor();
      expect(floor.runner.isGrounded, isTrue);
      expect(floor.speed, 0.0);
      for (var i = 0; i < 10; i++) {
        floor.step();
      }
      const mu = 0.68, g = 24.0;
      // A velocity is single precision.
      expect(floor.speed, closeTo(mu * g * 10 * _dt, 1e-5));
      for (var i = 0; i < 60; i++) {
        floor.step();
      }
      expect(floor.speed, closeTo(const MovementSettings().walkSpeed, 1e-5));
    },
  );

  test('water bearing a share of the weight leaves the legs that much less '
      'push, for the step it was written for', () {
    // A quarter of the weight held up: μ g · 0.75 a second, 2.04 m/s after
    // ten steps. And a step nobody writes the lift for is a step on dry
    // ground, μ g again.
    //
    // Mutation: leave the lift out of `Runner._gripped` and the ten steps
    // reach 2.72. Mutation: keep the lift from step to step rather than
    // setting it back to nought, and the last step gains 0.204 rather than
    // 0.272.
    final floor = _Floor();
    for (var i = 0; i < 10; i++) {
      floor.step(lift: 0.25);
    }
    const mu = 0.68, g = 24.0;
    expect(floor.speed, closeTo(mu * g * 0.75 * 10 * _dt, 1e-5));
    final before = floor.speed;
    floor.step();
    expect(floor.speed - before, closeTo(mu * g * _dt, 1e-5));
  });

  test('a grip of nothing is the controller pushing as it always did', () {
    // `RunnerSettings.grip` at zero switches the limit off: the controller's
    // 70 m/s², 3.5 m/s after three steps.
    //
    // Mutation: drop the early return for a grip of nothing, and the limit
    // becomes μ g = 0 and the runner never starts.
    final floor = _Floor(tuning: const RunnerSettings(grip: 0.0));
    for (var i = 0; i < 3; i++) {
      floor.step();
    }
    expect(
      floor.speed,
      closeTo(const MovementSettings().groundAcceleration * 3 * _dt, 1e-5),
    );
  });
}
