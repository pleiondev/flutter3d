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

  test('and having been pulled in, it stays where it was pulled to', () {
    // **The bug the whole "the penguin is drawn twice" report turned out to
    // be**, and it was not the penguin: it was every pixel on the screen.
    //
    // `keepOutOfWalls` wrote its answer into the vector being smoothed. So the
    // wall pulled the eye in to four metres, the smoother spent the next frame
    // easing from four back towards seven, the wall pulled it in again, and the
    // picture bounced by whatever fraction of that gap the lag closes — a
    // hundred and eighty millimetres a frame, measured with the runner
    // provably motionless, at twenty-seven places in the teaching level. At
    // sixty hertz that is not a wobble, it is a double exposure.
    //
    // The rule: **a constraint is not a state.** What is smoothed is where the
    // camera wants to be; where it is allowed to be is worked out from that
    // afresh each frame and thrown away.
    //
    // Mutation: point `keepOutOfWalls` back at the smoothed vector. Both
    // assertions below fail, and the second says by how much.
    final camera = FollowCamera(world: _walled());
    for (var i = 0; i < 240; i++) {
      camera.follow(Vector3.zero(), _frame);
    }

    final settled = camera.eye.clone();
    var worst = 0.0;
    for (var i = 0; i < 60; i++) {
      camera.follow(Vector3.zero(), _frame);
      final moved = (camera.eye - settled).length;
      if (moved > worst) worst = moved;
    }

    expect(worst, lessThan(0.001),
        reason: 'watching something that has not moved, the camera moved '
            '${(worst * 1000).toStringAsFixed(0)} mm');
  });

  test('and what is smoothed is never touched by the wall', () {
    // The same claim from the other side, and the one that would survive a
    // rewrite of how the pull-in works: whatever the wall does, the state the
    // lag runs on must converge on the free position.
    //
    // Mutation: as above. `freeEye` stops converging, because every frame it is
    // clamped back to the wall and has to climb out again.
    final camera = FollowCamera(world: _walled());
    for (var i = 0; i < 240; i++) {
      camera.follow(Vector3.zero(), _frame);
    }

    final free = camera.rig.freeEye.clone();
    for (var i = 0; i < 30; i++) {
      camera.follow(Vector3.zero(), _frame);
    }

    expect((camera.rig.freeEye - free).length, lessThan(1e-6),
        reason: 'the smoothed state has not converged');

    // And the two really are different things: the free eye is behind the wall,
    // where the camera wanted to be, and the shown one is in front of it. A
    // fix that simply stopped pulling in would pass the test above and fail
    // this one.
    expect(camera.rig.freeEye.z, lessThan(-2.0),
        reason: 'the free eye should be where the wall is not consulted');
    expect(camera.eye.z, greaterThan(-2.0),
        reason: 'the shown eye should still be in front of the wall');
  });

  test('and a kick is not smoothed either', () {
    // The same rule as the wall, applied to the other transient: an impulse is
    // something added on the way out, not something written into where the
    // camera thinks it is. Adding it to the state works — the kick decays and
    // the smoother climbs back — which is exactly why it needs a test: it is
    // wrong in a way that looks right.
    //
    // Mutation: `_eye.add(_kick)` instead of `_shown.add(_kick)`. The camera
    // still returns to where it was, so every other test here passes; what
    // changes is that a kick now drags the lag with it.
    final camera = FollowCamera(world: _empty());
    for (var i = 0; i < 240; i++) {
      camera.follow(Vector3.zero(), _frame);
    }

    final free = camera.rig.freeEye.clone();
    camera.kick(Vector3(0.0, -0.5, 0.0));
    camera.follow(Vector3.zero(), _frame);

    expect(camera.eye.y, lessThan(free.y - 0.3), reason: 'the kick did nothing');
    expect((camera.rig.freeEye - free).length, lessThan(1e-6),
        reason: 'the kick moved what the lag runs on');
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

  group('impulses', () {
    test('a kick moves the camera and then gives it back', () {
      // Mutation: forget the decay. The camera keeps the knock for the rest of
      // the level, which reads as the whole world having shifted.
      final camera = FollowCamera(world: _empty());
      final at = Vector3(0.0, 1.0, 0.0);
      for (var i = 0; i < 60; i++) {
        camera.follow(at, 1.0 / 60.0);
      }
      final settled = camera.eye.clone();

      camera.kick(Vector3(0.0, -0.4, 0.0));
      camera.follow(at, 1.0 / 60.0);
      expect((camera.eye.y - settled.y).abs(), greaterThan(0.05),
          reason: 'the kick did nothing');

      for (var i = 0; i < 60; i++) {
        camera.follow(at, 1.0 / 60.0);
      }
      expect(camera.eye.y, closeTo(settled.y, 0.01),
          reason: 'it never came back');
    });

    test('a shake is over inside half a second', () {
      final camera = FollowCamera(world: _empty());
      final at = Vector3(0.0, 1.0, 0.0);
      for (var i = 0; i < 60; i++) {
        camera.follow(at, 1.0 / 60.0);
      }
      final settled = camera.eye.clone();

      camera.shake(0.5);
      var worst = 0.0;
      for (var i = 0; i < 12; i++) {
        camera.follow(at, 1.0 / 60.0);
        final away = (camera.eye - settled).length;
        if (away > worst) worst = away;
      }
      expect(worst, greaterThan(0.01), reason: 'nothing shook');

      for (var i = 0; i < 60; i++) {
        camera.follow(at, 1.0 / 60.0);
      }
      expect((camera.eye - settled).length, lessThan(0.01),
          reason: 'it is still shaking');
    });

    test('turning the shake off turns it off', () {
      // The setting exists because a shaking camera makes some people ill, and
      // "off" has to mean off rather than "less".
      final camera = FollowCamera(world: _empty())..shakeScale = 0.0;
      final at = Vector3(0.0, 1.0, 0.0);
      for (var i = 0; i < 60; i++) {
        camera.follow(at, 1.0 / 60.0);
      }
      final settled = camera.eye.clone();

      camera.shake(2.0);
      for (var i = 0; i < 20; i++) {
        camera.follow(at, 1.0 / 60.0);
        expect((camera.eye - settled).length, lessThan(0.005));
      }
    });

    test('a shaken camera never ends up inside a wall', () {
      // The property the ordering exists for: the wall check runs first, so a
      // shake must be small enough that the clearance absorbs it. A hundred
      // random impulses in a boxed room, and the eye stays out of the geometry.
      // A room, not six floors: the first draft used the same flat slab for
      // every side, so the "walls" were horizontal and the camera was inside
      // three of them before anything was even shaken.
      final world = CollisionWorld();
      void slab(Vector3 at, Vector3 half) => world.add(
            Collider(
              shape: CollisionBox(half),
              position: at,
              layer: CollisionLayers.world,
            ),
          );
      slab(Vector3(0.0, -0.5, 0.0), Vector3(6.0, 0.5, 6.0));
      slab(Vector3(0.0, 6.5, 0.0), Vector3(6.0, 0.5, 6.0));
      slab(Vector3(-6.5, 3.0, 0.0), Vector3(0.5, 3.0, 6.0));
      slab(Vector3(6.5, 3.0, 0.0), Vector3(0.5, 3.0, 6.0));
      slab(Vector3(0.0, 3.0, -6.5), Vector3(6.0, 3.0, 0.5));
      slab(Vector3(0.0, 3.0, 6.5), Vector3(6.0, 3.0, 0.5));
      final camera = FollowCamera(world: world);
      final random = GameRandom(7);
      final inside = <Collider>[];

      for (var i = 0; i < 300; i++) {
        camera.follow(Vector3(0.0, 1.0, 0.0), 1.0 / 60.0);
        if (i % 20 == 0) {
          camera.kick(Vector3(random.nextDouble() - 0.5, random.nextDouble() - 0.5,
              random.nextDouble() - 0.5));
          camera.shake(random.nextDouble() * 0.3);
        }
        // A point, not a box, and the difference is the honest reading of the
        // invariant. One ray clears the *first* thing it hits, so a camera
        // pulled thirty-five centimetres off the ceiling can still end up a
        // millimetre from the wall behind it. Grazing a surface is a near
        // plane's problem — `nearClearance` — and being *inside* one is this
        // class's, which is what is asserted.
        world.overlap(CollisionBox(Vector3.all(1e-6)), camera.eye, inside,
            includeTriggers: false);
        expect(inside, isEmpty,
            reason: 'the camera was inside geometry on step $i, at '
                '${camera.eye}');
      }
    });

    test('a widened view narrows again', () {
      final camera = FollowCamera(world: _empty());
      camera.widen(0.3);
      expect(camera.extraFov, greaterThan(0.2));

      for (var i = 0; i < 90; i++) {
        camera.follow(Vector3.zero(), 1.0 / 60.0);
      }
      expect(camera.extraFov, lessThan(0.01));
    });
  });
}
