/// The camera is presentation, so none of this is about the simulation — it is
/// about the three ways a third-person camera goes wrong: it lags into walls,
/// it overshoots, and it flies across the level on the first frame.
library;

import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _frame = 1.0 / 60.0;

CollisionWorld _empty() => CollisionWorld();

/// A world with a wall two metres behind the origin, across the camera's path.
CollisionWorld _walled() {
  final world = CollisionWorld();
  world.addBox(Vector3(0.0, 2.0, -2.0), Vector3(20.0, 8.0, 0.5));
  return world;
}

void main() {
  test('the first frame is a cut, not a chase', () {
    // Mutation: drop the `_placed` branch and always smooth. The camera starts
    // at the origin and eases in, so every level begins with a second of
    // flying across it — which reads as a bug in the level, not the camera.
    final camera = FollowCamera(world: _empty())
      ..follow(Vector3(30.0, 0.0, 30.0), _frame);

    expect((camera.eye - Vector3(30.0, 0.0, 30.0)).length, lessThan(9.0));
  });

  test('it settles behind the runner and does not overshoot', () {
    final camera = FollowCamera(world: _empty())..follow(Vector3.zero(), _frame);

    // Walk the runner forward, one frame at a time, and watch the gap.
    var previous = double.infinity;
    for (var i = 1; i <= 120; i++) {
      final at = Vector3(0.0, 0.0, i * 0.1);
      camera.follow(at, _frame);
      final behind = at.z - camera.eye.z;
      // Always behind, never in front: an overshooting camera crosses over and
      // the player sees their own back from the wrong side.
      expect(behind, greaterThan(0.0), reason: 'frame $i');
      previous = behind;
    }
    // And it ends up trailing at about the distance it was asked for.
    expect(previous, closeTo(const FollowTuning().distance, 1.5));
  });

  test('lag is the same at 30 and 120 frames a second', () {
    // Mutation: use `lag * dt` directly instead of `1 - exp(-lag * dt)`. The
    // two runs then disagree by centimetres, which is the whole class of bug
    // where a game feels different on a better monitor.
    Vector3 after(double dt, int frames) {
      final camera = FollowCamera(world: _empty())..follow(Vector3.zero(), dt);
      for (var i = 0; i < frames; i++) {
        camera.follow(Vector3(0.0, 0.0, 10.0), dt);
      }
      return camera.eye.clone();
    }

    // A tenth of a second, which is *during* the catch-up rather than after
    // it. The first version of this ran a full second and passed with the
    // mutation in place: both forms converge, so comparing the settled state
    // compares nothing. A frame-rate bug lives in the transient.
    final slow = after(1.0 / 30.0, 3);
    final fast = after(1.0 / 120.0, 12);

    expect((slow - fast).length, lessThan(0.02));
  });

  test('a wall behind the runner pulls the camera in', () {
    // Mutation: skip `_keepOutOfWalls`. The camera settles seven metres back,
    // which is inside the wall, and the player spends the level looking at the
    // inside of a box.
    final camera = FollowCamera(world: _walled());
    for (var i = 0; i < 120; i++) {
      camera.follow(Vector3.zero(), _frame);
    }

    expect(camera.eye.z, greaterThan(-2.0), reason: 'not through the wall');
    expect((camera.eye - camera.target).length,
        lessThan(const FollowTuning().distance));
  });

  test('looking turns the camera and the pitch is clamped', () {
    final camera = FollowCamera(world: _empty());
    final before = camera.yaw;

    camera.look(Vector2(100.0, 0.0));
    expect(camera.yaw, isNot(before));

    for (var i = 0; i < 100; i++) {
      camera.look(Vector2(0.0, 1000.0));
    }
    expect(camera.pitch, greaterThanOrEqualTo(const FollowTuning().minPitch));

    for (var i = 0; i < 200; i++) {
      camera.look(Vector2(0.0, -1000.0));
    }
    expect(camera.pitch, lessThanOrEqualTo(const FollowTuning().maxPitch));
  });

  test('strafing goes to the camera\'s right, not its left', () {
    // **The test that was missing, and a player found what it would have.**
    // The one below holds forward only, and forward is symmetric in the sign
    // that was wrong — so A and D were swapped for the whole of the first
    // build and every test agreed with it.
    //
    // The camera at yaw 0 sits at -Z looking towards +Z. Screen-right is then
    // world -X, because right is `cross(forward, up)`. Mutation: flip the sign
    // of either `axis.x` term in `Runner._readWish`.
    final world = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0));
    final runner = Runner(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
    );
    final input = InputState()..press(GameAction.moveRight);

    for (var i = 0; i < 60; i++) {
      input.beginStep();
      runner.step(_frame, input, cameraYaw: 0.0);
      input.endStep();
    }

    expect(runner.position.x, lessThan(-2.0),
        reason: 'right of a camera looking along +Z is world -X');
    expect(runner.position.z.abs(), lessThan(0.5));
  });

  test('the yaw it reports is the forward the runner runs in', () {
    // The contract between the two: the camera owns "forward", and the runner
    // takes it as an argument. Turn the camera a quarter turn and forward is
    // world +X.
    final camera = FollowCamera(world: _empty(), yaw: math.pi / 2);
    final world = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
    final runner = Runner(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
    );
    final input = InputState()..press(GameAction.moveForward);

    for (var i = 0; i < 60; i++) {
      input.beginStep();
      runner.step(_frame, input, cameraYaw: camera.yaw);
      input.endStep();
    }

    expect(runner.position.x, greaterThan(2.0));
    expect(runner.position.z.abs(), lessThan(0.5));
  });
}
