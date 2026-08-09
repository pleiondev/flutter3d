import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:flutter3d/src/engine/render/material.dart';
import 'package:flutter3d/src/engine/scene/scene_graph.dart';

MeshNode level(String name) => MeshNode(
      CpuMesh(CuboidShape().build()),
      Material(),
      name: name,
    );

({Scene scene, LodGroup group, CameraNode camera}) build() {
  final scene = Scene();
  final group = LodGroup(
    name: 'rock',
    levels: <LodLevel>[
      // Finest first, and deliberately declared out of order so the
      // constructor's sort is doing something.
      LodLevel(node: level('medium'), maxScreenFraction: 0.2),
      LodLevel(node: level('high'), maxScreenFraction: 1.0),
      LodLevel(node: level('low'), maxScreenFraction: 0.05),
    ],
  );
  scene.add(group);

  final camera = scene.add(CameraNode(name: 'camera'))
    ..projection = const PerspectiveProjection(fovYRadians: math.pi / 2);
  camera.setPosition(0.0, 0.0, 5.0);
  camera.lookAt(Vector3.zero());

  return (scene: scene, group: group, camera: camera);
}

void main() {
  group('choosing a level', () {
    test('levels are ordered coarsest threshold first', () {
      final (:group, :scene, :camera) = build();
      expect(
        group.levels.map((l) => l.node.name),
        <String>['high', 'medium', 'low'],
      );
    });

    test('only one level is ever visible', () {
      final (:group, :scene, :camera) = build();
      for (final distance in <double>[1.0, 5.0, 30.0, 300.0]) {
        camera.setPosition(0.0, 0.0, distance);
        group.select(camera);
        expect(
          group.levels.where((l) => l.node.visible).length,
          1,
          reason: 'more than one level visible at distance $distance',
        );
      }
    });

    test('a near object gets the finest level', () {
      final (:group, :scene, :camera) = build();
      camera.setPosition(0.0, 0.0, 1.5);
      group.select(camera);
      expect(group.activeNode.name, 'high');
    });

    test('a distant object gets the coarsest', () {
      final (:group, :scene, :camera) = build();
      camera.setPosition(0.0, 0.0, 400.0);
      group.select(camera);
      expect(group.activeNode.name, 'low');
    });

    test('the level only ever coarsens as the camera pulls back', () {
      final (:group, :scene, :camera) = build();
      var previous = -1;
      for (var distance = 1.0; distance < 200.0; distance *= 1.3) {
        camera.setPosition(0.0, 0.0, distance);
        final chosen = group.select(camera);
        expect(chosen, greaterThanOrEqualTo(previous),
            reason: 'level went finer at distance $distance');
        previous = chosen;
      }
      expect(previous, group.levels.length - 1);
    });

    test('a wider field of view makes the same object smaller on screen', () {
      // The reason the threshold is a screen fraction and not a distance: the
      // same object at the same distance is worth different detail through
      // different lenses.
      final (:group, :scene, :camera) = build();
      camera.setPosition(0.0, 0.0, 6.0);

      final narrow = group.screenFraction(
        camera,
        verticalFieldOfView: math.pi / 8,
      );
      final wide = group.screenFraction(
        camera,
        verticalFieldOfView: math.pi / 2,
      );
      expect(narrow, greaterThan(wide));
    });

    test('an orthographic camera measures against its own height', () {
      final (:group, :scene, :camera) = build();
      camera.projection = const OrthographicProjection(height: 4.0);

      final near = group.screenFraction(camera);
      camera.setPosition(0.0, 0.0, 500.0);
      final far = group.screenFraction(camera);

      // Distance does not change an orthographic object's size, and treating it
      // as if it did is the classic way a LOD misbehaves in a plan view.
      expect(far, closeTo(near, 1e-9));
    });

    test('a camera inside the object sees it filling the frame', () {
      final (:group, :scene, :camera) = build();
      camera.setPosition(0.0, 0.0, 0.0);
      expect(group.screenFraction(camera), 1.0);
      expect(group.select(camera), 0);
    });

    test('the group refuses to be built with no levels', () {
      expect(
        () => LodGroup(levels: const <LodLevel>[]),
        throwsArgumentError,
      );
    });
  });

  group('interaction with the rest of the scene', () {
    test('hidden levels are skipped by culling and picking', () {
      // The point of hiding rather than detaching: everything downstream
      // already respects visibility, so nothing else has to learn about LODs.
      final (:group, :scene, :camera) = build();
      camera.setPosition(0.0, 0.0, 400.0);
      group.select(camera);

      final caster = Raycaster()
        ..ray.setFrom(Vector3(0.0, 0.0, 10.0), Vector3(0.0, 0.0, -1.0));
      final hit = caster.intersectScene(scene);

      expect(hit, isNotNull);
      expect(hit!.node!.name, 'low');
    });

    test('every level is still a child of the group', () {
      final (:group, :scene, :camera) = build();
      expect(scene.meshes.length, 3);
      for (final l in group.levels) {
        expect(l.node.parent, same(group));
      }
    });

    test('moving the group moves every level with it', () {
      final (:group, :scene, :camera) = build();
      group.setPosition(10.0, 0.0, 0.0);
      for (final l in group.levels) {
        expect(l.node.readWorldPosition().x, closeTo(10.0, 1e-6));
      }
    });
  });
}
