import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:flutter3d/src/engine/math/intersections.dart';
import 'package:flutter3d/src/engine/render/material.dart';
import 'package:flutter3d/src/engine/render/render_list.dart';
import 'package:flutter3d/src/engine/render/render_view.dart';
import 'package:flutter3d/src/engine/scene/scene_graph.dart';

/// A cube on the CPU, so none of this needs a device.
MeshNode cube({String? name}) => MeshNode(
      CpuMesh(CuboidShape().build()),
      Material(),
      name: name,
    );

/// A grid of cubes, deterministic so a failure reproduces.
Scene gridScene(int count, {double spacing = 3.0}) {
  final scene = Scene();
  final side = math.sqrt(count).ceil();
  for (var i = 0; i < count; i++) {
    final x = (i % side) - side / 2;
    final z = (i ~/ side) - side / 2;
    scene.add(cube(name: 'cube $i')).setPosition(x * spacing, ((i * 7) % 5) - 2.0, z * spacing);
  }
  return scene;
}

/// Everything the linear pass would consider visible, as a set of names.
Set<String> linearVisible(Scene scene, Frustum frustum) {
  final sphere = Sphere.centerRadius(Vector3.zero(), 1.0);
  final visible = <String>{};
  for (final node in scene.meshes) {
    if (!node.visibleInHierarchy) continue;
    sphere.center.setFrom(node.worldBoundsCentre);
    sphere.radius = node.worldBoundsRadius;
    if (frustum.intersectsWithSphere(sphere)) visible.add(node.name!);
  }
  return visible;
}

/// Refreshes [bvh] from the scene, the way the render list does.
void refreshFromScene(SceneBvh bvh, Scene scene) {
  final spheres = ensureSphereCapacity(Float32List(0), scene.meshes.length);
  bvh.refresh(
    spheres,
    scene.meshes.length,
    packSceneSpheres(scene.meshes, spheres),
  );
}

Set<String> bvhVisible(SceneBvh bvh, Scene scene, Frustum frustum) {
  final sphere = Sphere.centerRadius(Vector3.zero(), 1.0);
  final visible = <String>{};
  refreshFromScene(bvh, scene);
  bvh.queryFrustum(frustum, (index) {
    final node = scene.meshes[index];
    if (!node.visibleInHierarchy) return;
    sphere.center.setFrom(node.worldBoundsCentre);
    sphere.radius = node.worldBoundsRadius;
    if (frustum.intersectsWithSphere(sphere)) visible.add(node.name!);
  });
  return visible;
}

Frustum frustumFor(Scene scene, {double distance = 40.0, double yaw = 0.0}) {
  final camera = scene.add(CameraNode(name: 'probe camera'))
    ..projection = const PerspectiveProjection(near: 0.5, far: 200.0);
  camera.setPosition(
    math.sin(yaw) * distance,
    distance * 0.4,
    math.cos(yaw) * distance,
  );
  camera.lookAt(Vector3.zero());
  final frustum = Frustum.matrix(camera.viewProjection(16.0 / 9.0));
  camera.removeFromParent();
  return frustum;
}

void main() {
  group('the tree returns the same visible set as a linear pass', () {
    // The single invariant that matters. A tree that is merely fast is worth
    // nothing if it drops an object, and a dropped object is invisible in a
    // screenshot until it happens to be the one you were looking at.
    test('for a grid of objects, from several angles', () {
      final scene = gridScene(600);
      final bvh = SceneBvh();

      for (final yaw in <double>[0.0, 0.7, 1.9, 3.4, 5.1]) {
        final frustum = frustumFor(scene, yaw: yaw);
        expect(
          bvhVisible(bvh, scene, frustum),
          linearVisible(scene, frustum),
          reason: 'visible sets differ at yaw $yaw',
        );
      }
    });

    test('when the camera is inside the grid', () {
      final scene = gridScene(400);
      final bvh = SceneBvh();
      final frustum = frustumFor(scene, distance: 2.0);
      expect(bvhVisible(bvh, scene, frustum), linearVisible(scene, frustum));
    });

    test('when everything is off screen', () {
      final scene = gridScene(200);
      final bvh = SceneBvh();
      // Looking away from the grid entirely.
      final camera = scene.add(CameraNode())..setPosition(0.0, 0.0, 400.0);
      camera.lookAt(Vector3(0.0, 0.0, 1000.0));
      final frustum = Frustum.matrix(camera.viewProjection(1.0));

      expect(bvhVisible(bvh, scene, frustum), isEmpty);
      expect(linearVisible(scene, frustum), isEmpty);
    });

    test('after an object moves', () {
      final scene = gridScene(600);
      final bvh = SceneBvh();
      final frustum = frustumFor(scene);
      bvhVisible(bvh, scene, frustum);
      final before = bvh.rebuildCount;

      // Move one object a long way; the tree it was in no longer bounds it.
      scene.meshes.first.setPosition(500.0, 500.0, 500.0);

      expect(bvhVisible(bvh, scene, frustum), linearVisible(scene, frustum));
      expect(bvh.rebuildCount, greaterThan(before),
          reason: 'a moved object must invalidate the tree');
    });

    test('after objects are added and removed', () {
      final scene = gridScene(600);
      final bvh = SceneBvh();
      final frustum = frustumFor(scene);
      bvhVisible(bvh, scene, frustum);

      scene.add(cube(name: 'newcomer')).setPosition(0.0, 0.0, 0.0);
      expect(bvhVisible(bvh, scene, frustum), linearVisible(scene, frustum));

      scene.meshes[10].removeFromParent();
      expect(bvhVisible(bvh, scene, frustum), linearVisible(scene, frustum));
    });

    test('when every object sits at the same point', () {
      // A degenerate build: no axis has any spread, so the median split cannot
      // separate anything by position and has to fall back on counting.
      final scene = Scene();
      for (var i = 0; i < 100; i++) {
        scene.add(cube(name: 'stacked $i'));
      }
      final bvh = SceneBvh();
      final frustum = frustumFor(scene, distance: 10.0);
      expect(bvhVisible(bvh, scene, frustum), linearVisible(scene, frustum));
    });
  });

  group('rebuilding', () {
    test('a static scene rebuilds once', () {
      final scene = gridScene(600);
      final bvh = SceneBvh();
      final frustum = frustumFor(scene);

      for (var i = 0; i < 10; i++) {
        bvhVisible(bvh, scene, frustum);
      }
      expect(bvh.rebuildCount, 1);
    });

    test('an empty scene is not a crash', () {
      final bvh = SceneBvh()..refresh(Float32List(0), 0, 1);
      expect(bvh.isEmpty, isTrue);
      expect(
        () => bvh.queryFrustum(frustumFor(Scene()), (_) {}),
        returnsNormally,
      );
    });
  });

  group('ray queries', () {
    test('find the same nearest hit as the linear path', () {
      final scene = gridScene(600, spacing: 4.0);
      final list = RenderList();

      final linear = Raycaster()
        ..ray.setFrom(Vector3(0.0, 0.0, 200.0), Vector3(0.0, 0.0, -1.0));
      final expected = linear.intersectScene(scene);

      final accelerated = Raycaster()
        ..bvh = list.bvh
        ..ray.setFrom(Vector3(0.0, 0.0, 200.0), Vector3(0.0, 0.0, -1.0));
      final actual = accelerated.intersectScene(scene);

      expect(actual?.node?.name, expected?.node?.name);
      if (expected != null) {
        expect(actual!.distance, closeTo(expected.distance, 1e-5));
      }
    });

    test('a ray that misses everything still misses with a tree', () {
      final scene = gridScene(600);
      final caster = Raycaster()
        ..bvh = SceneBvh()
        ..ray.setFrom(Vector3(0.0, 900.0, 0.0), Vector3(0.0, 1.0, 0.0));
      expect(caster.intersectScene(scene), isNull);
    });

    test('the tree visits fewer nodes than the linear pass', () {
      // The whole point: the win is in the work not done.
      final scene = gridScene(2000, spacing: 6.0);
      final bvh = SceneBvh();
      refreshFromScene(bvh, scene);

      var visited = 0;
      final ray = Ray(Vector3(0.0, 0.0, 400.0), Vector3(0.0, 0.0, -1.0));
      bvh.queryRay(ray, (_) => visited++);

      expect(visited, greaterThan(0));
      expect(visited, lessThan(scene.meshes.length ~/ 4),
          reason: 'visited $visited of ${scene.meshes.length}');
    });
  });

  group('the render list threshold', () {
    test('a small scene stays on the linear path', () {
      final scene = gridScene(10);
      final list = RenderList();
      final camera = scene.add(CameraNode())..setPosition(0.0, 0.0, 40.0);
      camera.lookAt(Vector3.zero());

      list.build(
        scene,
        RenderView(camera: camera),
        viewMatrix: camera.viewMatrix,
        frustum: Frustum.matrix(camera.viewProjection(1.0)),
      );
      expect(list.usedBvh, isFalse);
      expect(list.bvh.rebuildCount, 0);
    });

    test('a large scene uses the tree and finds the same draws', () {
      final scene = gridScene(RenderList.bvhThreshold + 100);
      final camera = scene.add(CameraNode())..setPosition(0.0, 30.0, 90.0);
      camera.lookAt(Vector3.zero());
      final view = RenderView(camera: camera);
      final frustum = Frustum.matrix(camera.viewProjection(1.0));

      final accelerated = RenderList()
        ..build(scene, view, viewMatrix: camera.viewMatrix, frustum: frustum);
      expect(accelerated.usedBvh, isTrue);

      // No `..remove(null)`: `linearVisible` answers `Set<String>`, so the call
      // never removed anything and only read as though unnamed nodes were being
      // filtered out. The 3.47 analyser flags it as unrelated-type.
      final expected = linearVisible(scene, frustum);
      final actual = <String>{
        for (var i = 0; i < accelerated.length; i++)
          accelerated.itemAt(i).requireNode.name!,
      };
      expect(actual, expected);
    });
  });
}
