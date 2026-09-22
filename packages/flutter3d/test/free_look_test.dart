/// `ux-04`'s own second camera: looking around from where the camera stands,
/// and walking it with the keys.
///
///     flutter test test/free_look_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_core/src/engine/scene/scene_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Where the camera stands, read off the node the controller actually drove
/// rather than recomputed from the same three numbers the code under test
/// used — so a sign error in `apply` cannot agree with itself.
Vector3 _eye(SceneNode node) => node.readWorldPosition();

/// The direction the camera is facing, from its own matrix.
Vector3 _forward(SceneNode node) {
  final m = node.worldMatrix.storage;
  return Vector3(-m[8], -m[9], -m[10])..normalize();
}

void main() {
  group('free look', () {
    test('turning the head leaves the camera where it stands', () {
      final node = SceneNode();
      final orbit = OrbitController(node, distance: 4.0);
      final look = FreeLook(orbit);
      final Vector3 before = _eye(node).clone();

      look.look(120.0, -40.0);

      // The whole difference from an orbit: an orbit would have swung the
      // camera round the target by this much, which over 120 pixels is most
      // of a quarter turn.
      expect((_eye(node) - before).length, lessThan(1e-5));
    });

    test('and turns the view the same way an orbit turns it', () {
      final node = SceneNode();
      final orbit = OrbitController(node, distance: 4.0, pitch: 0.0);
      final Vector3 orbited = () {
        orbit.rotate(60.0, 0.0);
        return _forward(node);
      }();

      final SceneNode other = SceneNode();
      final second = OrbitController(other, distance: 4.0, pitch: 0.0);
      FreeLook(second).look(60.0, 0.0);

      // Same angles, different pivot: the direction the person ends up
      // facing is the same under both cameras, which is what makes the
      // handover between them unremarkable.
      expect(_forward(other).dot(orbited), closeTo(1.0, 1e-6));
    });

    test('the target lands ahead of the camera, a full distance out', () {
      final node = SceneNode();
      final orbit = OrbitController(node, distance: 6.0);
      final look = FreeLook(orbit);

      look.look(80.0, 30.0);

      final Vector3 toTarget = orbit.target - _eye(node);
      expect(toTarget.length, closeTo(6.0, 1e-5));
      expect((toTarget..normalize()).dot(_forward(node)), closeTo(1.0, 1e-6));
    });

    test(
      'the pitch is clamped, and a clamped look does not slide sideways',
      () {
        final node = SceneNode();
        final orbit = OrbitController(node, distance: 3.0);
        final look = FreeLook(orbit);
        look.look(0.0, 1e6);
        final Vector3 atThePole = _eye(node).clone();

        // Already against the clamp: asking for more must move nothing at all,
        // rather than walking the camera round the last legal circle.
        look.look(0.0, 1e6);

        expect(orbit.pitch.abs(), lessThan(math.pi / 2));
        expect((_eye(node) - atThePole).length, lessThan(1e-6));
      },
    );

    test(
      'walking forward moves along the view direction, at its own speed',
      () {
        final node = SceneNode();
        final orbit = OrbitController(node, distance: 5.0);
        final look = FreeLook(orbit)..metresPerSecond = 2.0;
        final Vector3 before = _eye(node).clone();
        final Vector3 facing = _forward(node).clone();

        look.walk(forward: 1.0, seconds: 0.5);

        final Vector3 moved = _eye(node) - before;
        expect(moved.length, closeTo(1.0, 1e-6));
        expect((moved..normalize()).dot(facing), closeTo(1.0, 1e-6));
      },
    );

    test('and keeps the distance, so letting go orbits what is ahead', () {
      final node = SceneNode();
      final orbit = OrbitController(node, distance: 5.0);
      final look = FreeLook(orbit);

      look
        ..look(40.0, 10.0)
        ..walk(forward: 1.0, right: 1.0, seconds: 1.0);

      expect(orbit.distance, closeTo(5.0, 1e-12));
      expect((orbit.target - _eye(node)).length, closeTo(5.0, 1e-5));
    });

    test('a diagonal is no faster than a straight line', () {
      final Vector3 straight = _walked(forward: 1.0);
      final Vector3 diagonal = _walked(forward: 1.0, right: 1.0);

      // A loose-looking tolerance for an exact-looking claim: a node's own
      // transform is stored as 32-bit floats, so reading the eye back off it
      // costs about a part in ten million however the arithmetic went.
      expect(diagonal.length, closeTo(straight.length, 1e-6));
    });

    test('right walks to screen right, up walks to world up', () {
      final node = SceneNode();
      // Yaw and pitch both off zero, so "up" following the camera instead of
      // the world would show as a tilt in the answer.
      final orbit = OrbitController(node, distance: 4.0, yaw: 0.9, pitch: 0.7);
      final look = FreeLook(orbit)..metresPerSecond = 1.0;
      final Vector3 before = _eye(node).clone();

      look.walk(up: 1.0, seconds: 1.0);

      final Vector3 moved = _eye(node) - before;
      expect(moved.x, closeTo(0.0, 1e-6));
      expect(moved.y, closeTo(1.0, 1e-6));
      expect(moved.z, closeTo(0.0, 1e-6));
    });

    test('the two modifiers scale the step and nothing else', () {
      final Vector3 plain = _walked(forward: 1.0);
      final Vector3 slow = _walked(forward: 1.0, slow: true);
      final Vector3 fast = _walked(forward: 1.0, fast: true);

      expect(slow.length, closeTo(plain.length * 0.25, 1e-6));
      expect(fast.length, closeTo(plain.length * 4.0, 1e-6));
      expect(
        (slow.clone()..normalize()).dot(plain..normalize()),
        closeTo(1, 1e-6),
      );
    });

    test('no keys and no time move nothing', () {
      expect(_walked().length, closeTo(0.0, 1e-12));
      expect(_walked(forward: 1.0, seconds: 0.0).length, closeTo(0.0, 1e-12));
    });
  });
}

/// One walk from a fresh camera, answering how far the eye moved.
Vector3 _walked({
  double forward = 0.0,
  double right = 0.0,
  double up = 0.0,
  double seconds = 1.0,
  bool slow = false,
  bool fast = false,
}) {
  final node = SceneNode();
  final orbit = OrbitController(node, distance: 4.0, yaw: 0.4, pitch: 0.3);
  final Vector3 before = node.readWorldPosition().clone();
  FreeLook(orbit)
    ..metresPerSecond = 2.0
    ..walk(
      forward: forward,
      right: right,
      up: up,
      seconds: seconds,
      slow: slow,
      fast: fast,
    );
  return node.readWorldPosition() - before;
}
