import 'dart:math' as math;

import 'package:flutter3d/src/engine/scene/scene_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('orbit controller', () {
    test('places the node at the requested distance from the target', () {
      final node = SceneNode();
      final orbit = OrbitController(node, distance: 7.0);
      final offset = node.readWorldPosition() - orbit.target;
      expect(offset.length, closeTo(7.0, 1e-5));
    });

    test('always faces the target', () {
      final node = SceneNode();
      final orbit = OrbitController(node);
      orbit.rotate(120.0, -60.0);

      final m = node.worldMatrix.storage;
      final forward = Vector3(-m[8], -m[9], -m[10])..normalize();
      final toTarget = (orbit.target - node.readWorldPosition())..normalize();
      expect(forward.dot(toTarget), closeTo(1.0, 1e-4));
    });

    test('pitch is clamped short of the poles', () {
      final orbit = OrbitController(SceneNode());
      orbit.rotate(0.0, 1e6);
      expect(orbit.pitch, lessThan(math.pi / 2));
      orbit.rotate(0.0, -1e6);
      expect(orbit.pitch, greaterThan(-math.pi / 2));
    });

    test('zoom is multiplicative and clamped', () {
      final orbit = OrbitController(
        SceneNode(),
        distance: 10.0,
        minDistance: 1.0,
        maxDistance: 100.0,
      );
      orbit.zoom(0.5);
      expect(orbit.distance, closeTo(5.0, 1e-6));

      orbit.zoom(1e-6);
      expect(orbit.distance, closeTo(1.0, 1e-6));
      orbit.zoom(1e6);
      expect(orbit.distance, closeTo(100.0, 1e-6));
    });

    test('frameBounds centres the target and fits the bounds', () {
      final orbit = OrbitController(SceneNode());
      final bounds = Aabb3.minMax(
        Vector3(2.0, 2.0, 2.0),
        Vector3(4.0, 4.0, 4.0),
      );
      orbit.frameBounds(bounds, fovYRadians: math.pi / 4);

      expect(orbit.target.x, closeTo(3.0, 1e-6));
      // The sphere around a 2-unit cube has radius sqrt(3); at a 45 degree fov
      // the camera must sit at least that far divided by sin(fov/2).
      final radius = math.sqrt(3.0);
      expect(orbit.distance, greaterThan(radius));
    });

    test('suggested depth range brackets the orbit distance', () {
      final orbit = OrbitController(SceneNode(), distance: 20.0);
      final range = orbit.suggestedDepthRange();
      expect(range.near, greaterThan(0.0));
      expect(range.near, lessThan(20.0));
      expect(range.far, greaterThan(20.0));
    });

    test('syncProjectionDepth updates a perspective camera only', () {
      final camera = CameraNode(
        projection: const PerspectiveProjection(near: 0.1, far: 1000.0),
      );
      final orbit = OrbitController(camera, distance: 50.0);
      orbit.syncProjectionDepth(camera);

      // Assert the relationship rather than magic numbers: the range must
      // bracket the orbit distance, which is what keeps precision on the model.
      final projection = camera.projection as PerspectiveProjection;
      expect(projection.near, lessThan(orbit.distance));
      expect(projection.far, greaterThan(orbit.distance));
      expect(projection.near, greaterThan(0.0));

      final ortho = CameraNode(projection: const OrthographicProjection());
      OrbitController(ortho).syncProjectionDepth(ortho);
      expect(ortho.projection, isA<OrthographicProjection>());
    });

    test('an orthographic camera is zoomed by its height', () {
      final camera = CameraNode(projection: const OrthographicProjection());
      final orbit = OrbitController(camera, distance: 10.0);
      orbit.syncProjectionDepth(camera);
      final before = (camera.projection as OrthographicProjection).height;

      orbit.zoom(0.5);
      orbit.syncProjectionDepth(camera);
      final after = (camera.projection as OrthographicProjection).height;

      // Mutation: leave `height` out of `syncProjectionDepth`'s orthographic
      // arm and a wheel does nothing at all in an orthographic viewport — the
      // camera walks towards a model that stays exactly the size it was, which
      // is what an orthographic projection means and why the height has to
      // carry the zoom.
      expect(after, closeTo(before * 0.5, 1e-6));
    });

    test('an orthographic picture does not depend on the distance', () {
      final camera = CameraNode(projection: const OrthographicProjection());
      final orbit = OrbitController(camera, distance: 10.0);
      orbit.syncProjectionDepth(camera);
      final before = (camera.projection as OrthographicProjection).height;

      // The camera walked back without anybody asking for a zoom, which is what
      // clearing geometry off the near plane looks like.
      orbit.distance = 40.0;
      orbit.apply();
      orbit.syncProjectionDepth(camera);

      // Mutation: derive the height from the distance instead of keeping it,
      // and this is four times what it was — the model shrinks to a quarter
      // because the camera moved, in the one projection where moving the camera
      // along the view axis is defined not to matter.
      expect(
        (camera.projection as OrthographicProjection).height,
        closeTo(before, 1e-6),
      );
    });

    test('the two lenses frame the same bounds the same size', () {
      final bounds = Aabb3.minMax(Vector3(-1, -1, -1), Vector3(1, 1, 1));
      final orbit = OrbitController(SceneNode());
      orbit.frameBounds(bounds, fovYRadians: math.pi / 4);

      // What a perspective camera shows at the target's own depth, against what
      // the orthographic lens was told to show. Mutation: frame the sphere's
      // own diameter instead — `orthoHeight = 2 * radius * margin`, which reads
      // like the more obviously correct thing — and this comes out at 4.33
      // against 4.69, so switching a viewport between the two lenses makes the
      // model jump eight per cent.
      final perspective = 2.0 * orbit.distance * math.tan(math.pi / 8);
      expect(orbit.orthoHeight, closeTo(perspective, 1e-4));
    });

    test('a zoom refused by the clamp does not move the height either', () {
      final orbit = OrbitController(
        SceneNode(),
        distance: 1.0,
        minDistance: 1.0,
        maxDistance: 100.0,
      );
      final before = orbit.orthoHeight;
      orbit.zoom(0.01);

      // Mutation: scale the height by the factor asked for rather than by the
      // distance that resulted, and a wheel spun at the near clamp keeps
      // shrinking the orthographic picture with nothing on screen moving —
      // until the viewport is switched to that lens and the model has silently
      // become a hundred times too big.
      expect(orbit.distance, closeTo(1.0, 1e-9));
      expect(orbit.orthoHeight, closeTo(before, 1e-9));
    });

    test('animateTo arrives, and takes the time it was given', () {
      final orbit = OrbitController(SceneNode(), yaw: 0.0, pitch: 0.0);
      orbit.animateTo(yaw: 1.0, seconds: 0.2);

      expect(orbit.isTurning, isTrue);
      orbit.advance(0.05);
      // A quarter of the time and well short of a quarter of the turn, because
      // the view is still getting under way. Mutation: drop the easing and hold
      // the yaw linear, and this is 0.25 — a turn that leaves at full speed and
      // arrives at full speed, which the eye reads as the picture being yanked
      // rather than moved. The midpoint would have shown nothing: smoothstep
      // and a straight line agree at exactly one half.
      expect(orbit.yaw, closeTo(0.15625, 1e-9));
      orbit.advance(0.05);
      expect(orbit.yaw, closeTo(0.5, 1e-9));
      expect(orbit.isTurning, isTrue);

      orbit.advance(1.0);
      expect(orbit.yaw, closeTo(1.0, 1e-9));
      expect(orbit.isTurning, isFalse);
      // And it stays there: an advance past the end must not carry on turning.
      orbit.advance(1.0);
      expect(orbit.yaw, closeTo(1.0, 1e-9));
    });

    test('a turn takes the short way round the seam', () {
      final orbit = OrbitController(SceneNode(), yaw: 3.0);
      // Just under a half turn to just over one, the other way. Mutation:
      // interpolate the two yaws directly and the model spins nearly all the
      // way round to reach a view a few degrees away.
      orbit.animateTo(yaw: -3.0, seconds: 1.0);
      orbit.advance(0.5);

      // Halfway along the short arc is past the seam, not back near zero.
      expect(orbit.yaw.abs(), greaterThan(3.1));
    });

    test('a hand on the mouse ends a turn in progress', () {
      final orbit = OrbitController(SceneNode(), yaw: 0.0);
      orbit.animateTo(yaw: 1.0, seconds: 1.0);
      orbit.rotate(10.0, 0.0);
      final interrupted = orbit.yaw;
      orbit.advance(1.0);

      // Mutation: leave the turn running through `rotate`, and the view walks
      // back to where the animation was going while somebody is dragging it —
      // the drag and the animation fight, and the drag loses.
      expect(orbit.isTurning, isFalse);
      expect(orbit.yaw, closeTo(interrupted, 1e-9));
    });

    test('a turn of no time arrives at once', () {
      final orbit = OrbitController(SceneNode(), yaw: 0.0, pitch: 0.0);
      orbit.animateTo(yaw: 2.0, pitch: 0.3, seconds: 0.0);

      // What the orientation gizmo does when somebody has turned animation off,
      // and what a test that only wants the view moved asks for.
      expect(orbit.yaw, closeTo(2.0, 1e-9));
      expect(orbit.pitch, closeTo(0.3, 1e-9));
      expect(orbit.isTurning, isFalse);
    });

    test('a turn cannot be aimed past the pole', () {
      final orbit = OrbitController(SceneNode());
      orbit.animateTo(pitch: math.pi, seconds: 0.0);

      // Mutation: skip the clamp in `animateTo` and a gizmo's "top" view puts
      // the pitch at a right angle, where the up vector is ambiguous and the
      // picture snaps round as the next drag crosses it.
      expect(orbit.pitch, lessThan(math.pi / 2));
      expect(orbit.pitch, greaterThan(math.pi / 2 - 0.05));
    });

    test('pan moves the target across the view plane', () {
      final orbit = OrbitController(SceneNode(), distance: 10.0);
      final before = orbit.target.clone();
      orbit.pan(50.0, 0.0, viewportHeight: 600.0);
      expect((orbit.target - before).length, greaterThan(0.0));
      // Panning sideways must not change the orbit radius.
      final offset = orbit.node.readWorldPosition() - orbit.target;
      expect(offset.length, closeTo(10.0, 1e-5));
    });
  });
}
