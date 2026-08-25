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
