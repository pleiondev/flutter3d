/// The photo-mode camera, and the three ways it is held inside the level —
/// `N8`.
///
///     dart test test/photo_camera_test.dart
///
/// A free camera is easy; the claims here are about where it cannot go. Each
/// test names the line whose removal would let it through.
library;

import 'dart:math' as math;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A closed room twenty metres square and six high, walls half a metre thick,
/// with a pillar in the middle of its −Z half. The boxes are kept so a test can
/// ask whether a point is inside one without going through the code under test.
({CollisionWorld world, List<Aabb3> solids}) _room() {
  final world = CollisionWorld();
  final solids = <Aabb3>[];
  void box(Vector3 centre, Vector3 size) {
    world.addBox(centre, size);
    solids.add(Aabb3.centerAndHalfExtents(centre, size / 2.0));
  }

  box(Vector3(0.0, -0.25, 0.0), Vector3(21.0, 0.5, 21.0)); // floor
  box(Vector3(0.0, 6.25, 0.0), Vector3(21.0, 0.5, 21.0)); // ceiling
  box(Vector3(10.25, 3.0, 0.0), Vector3(0.5, 6.0, 21.0));
  box(Vector3(-10.25, 3.0, 0.0), Vector3(0.5, 6.0, 21.0));
  box(Vector3(0.0, 3.0, 10.25), Vector3(21.0, 6.0, 0.5));
  box(Vector3(0.0, 3.0, -10.25), Vector3(21.0, 6.0, 0.5));
  box(Vector3(0.0, 3.0, -5.0), Vector3(2.0, 6.0, 2.0)); // pillar
  world.update();
  return (world: world, solids: solids);
}

bool _inside(List<Aabb3> solids, Vector3 point) =>
    solids.any((box) => box.containsVector3(point));

void main() {
  test('begins looking where the game camera looked', () {
    final room = _room();
    final camera = PhotoCamera(world: room.world)
      ..begin(
        eye: Vector3(0.0, 2.0, 6.0),
        target: Vector3(3.0, 1.0, 2.0),
        anchor: Vector3(0.0, 1.0, 4.0),
      );
    final wanted = (Vector3(3.0, 1.0, 2.0) - Vector3(0.0, 2.0, 6.0))
      ..normalize();
    // Mutation: swap the arguments of the `atan2` in `begin`. The camera opens
    // ninety degrees off the shot the player paused to take.
    expect(camera.forward.distanceTo(wanted), lessThan(1e-6));
    expect(camera.eye.distanceTo(Vector3(0.0, 2.0, 6.0)), lessThan(1e-6));
  });

  test('a chase camera behind a wall starts on the player\'s side of it', () {
    final room = _room();
    // The player stands just in front of the pillar, and the game's camera has
    // been left on its far side — where a chase camera ends up for a frame
    // when the player turns sharply.
    final camera = PhotoCamera(world: room.world)
      ..begin(
        eye: Vector3(0.0, 2.0, -8.0),
        target: Vector3(0.0, 2.0, 0.0),
        anchor: Vector3(0.0, 2.0, -2.0),
      );
    // Mutation: `_eye.setFrom(eye)` in `begin` instead of sweeping to it from
    // the anchor. The first picture is taken from inside the level's far side
    // of a wall the player is standing in front of.
    expect(camera.eye.z, greaterThan(-4.0 + 0.2 - 1e-3));
    expect(_inside(room.solids, camera.eye), isFalse);
  });

  test('flying into a wall stops in front of it', () {
    final room = _room();
    final camera = PhotoCamera(world: room.world, reach: 50.0)
      ..begin(
        eye: Vector3(0.0, 2.0, 4.0),
        target: Vector3(0.0, 2.0, 20.0),
        anchor: Vector3(0.0, 2.0, 4.0),
      );
    for (var i = 0; i < 300; i++) {
      camera.fly(Vector3(0.0, 0.0, 1.0), 1.0 / 60.0);
    }
    // Mutation: `point.add(delta)` in place of the sweep in `_slide`. Five
    // seconds at four metres a second carries the eye through the wall at
    // z = 10 and out of the level.
    expect(camera.eye.z, lessThanOrEqualTo(10.0 - 0.2 + 1e-2));
    expect(camera.eye.z, greaterThan(9.0), reason: 'it did get there');
  });

  test('flying along a wall at a slant slides rather than sticks', () {
    final room = _room();
    final camera = PhotoCamera(world: room.world, reach: 50.0)
      ..begin(
        eye: Vector3(-5.0, 2.0, 9.5),
        target: Vector3(-5.0, 2.0, 20.0),
        anchor: Vector3(-5.0, 2.0, 9.5),
      );
    camera.look(math.pi / 4.0, 0.0);
    for (var i = 0; i < 60; i++) {
      camera.fly(Vector3(0.0, 0.0, 1.0), 1.0 / 60.0);
    }
    // Mutation: stop at the first hit in `_slide` rather than keeping the part
    // of the move that runs along the wall. A camera pressed against a wall at
    // forty-five degrees then freezes, and lining up a shot along a corridor
    // is impossible.
    expect(camera.eye.x, greaterThan(-5.0 + 2.0));
    expect(camera.eye.z, lessThanOrEqualTo(10.0 - 0.2 + 1e-2));
  });

  test('the tether holds the camera within reach of the player', () {
    final room = _room();
    final camera = PhotoCamera(world: room.world, reach: 6.0)
      ..begin(
        eye: Vector3(5.0, 2.0, 5.0),
        target: Vector3(-5.0, 2.0, 5.0),
        anchor: Vector3(5.0, 1.0, 5.0),
      );
    for (var i = 0; i < 600; i++) {
      camera.fly(Vector3(0.3, 0.2, 1.0), 1.0 / 60.0);
    }
    // Mutation: drop the reach clamp in `_allowed`. Ten seconds of flying
    // takes the camera to the room's far wall, eleven metres from the player.
    expect(camera.eye.distanceTo(camera.anchor), lessThanOrEqualTo(6.0 + 1e-2));
    expect(
      camera.fly(Vector3(0.0, 0.0, 1.0), 1.0 / 60.0),
      isTrue,
      reason: 'and says it was held, so a game can show the edge',
    );
  });

  test('the level box holds the camera where no wall does', () {
    // No ceiling and no floor in this world, only the box — a level on a slab
    // with open sky above it.
    final world = CollisionWorld()..update();
    final camera =
        PhotoCamera(
          world: world,
          reach: 100.0,
          bounds: Aabb3.minMax(
            Vector3(-4.0, 0.0, -4.0),
            Vector3(4.0, 3.0, 4.0),
          ),
        )..begin(
          eye: Vector3(0.0, 1.0, 0.0),
          target: Vector3(0.0, -1.0, 0.0),
          anchor: Vector3(0.0, 1.0, 0.0),
        );
    for (var i = 0; i < 120; i++) {
      camera.fly(Vector3(0.0, -1.0, 0.0), 1.0 / 60.0);
    }
    // Mutation: drop the box clamp in `_allowed`. The camera goes under the
    // level and photographs the underside of the floor.
    expect(camera.eye.y, greaterThanOrEqualTo(0.0 + 0.2 - 1e-9));
  });

  test('five hundred random moves in a furnished room never leave it', () {
    // The property `CameraRig` was held to, three hundred random impulses in a
    // boxed room; this is the same check for a camera the player steers.
    final room = _room();
    final random = math.Random(8);
    final camera = PhotoCamera(world: room.world, reach: 9.0)
      ..begin(
        eye: Vector3(0.0, 2.0, 3.0),
        target: Vector3(0.0, 2.0, -3.0),
        anchor: Vector3(0.0, 1.0, 3.0),
      );
    double signed() => random.nextDouble() * 2.0 - 1.0;
    for (var i = 0; i < 500; i++) {
      camera
        ..look(signed() * 0.8, signed() * 0.6)
        ..fly(Vector3(signed(), signed(), signed()) * 3.0, 0.25);
      // Mutation: sweep with the camera's own size halved in `_shape`. The
      // walk ends a step with the eye a few centimetres into the floor, the
      // ceiling or the pillar, which is the near plane cutting into a wall.
      expect(_inside(room.solids, camera.eye), isFalse, reason: 'step $i');
      expect(
        camera.eye.distanceTo(camera.anchor),
        lessThanOrEqualTo(9.0 + 1e-2),
        reason: 'step $i',
      );
    }
  });

  test('a tilted camera keeps its up at right angles to where it looks', () {
    final camera = PhotoCamera(world: CollisionWorld()..update())
      ..begin(
        eye: Vector3.zero(),
        target: Vector3(0.0, -0.5, -1.0),
        anchor: Vector3.zero(),
      )
      ..tilt(10.0)
      ..zoom(100.0);
    // Mutation: drop the `maxRoll` clamp in `tilt`. The horizon turns past
    // vertical and the picture is upside down.
    expect(camera.roll, closeTo(math.pi / 4.0, 1e-9));
    expect(camera.up.dot(camera.forward).abs(), lessThan(1e-6));
    expect(camera.up.length, closeTo(1.0, 1e-6));
    expect(camera.fieldOfView, camera.minFieldOfView);
  });
}
