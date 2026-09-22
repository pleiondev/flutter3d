/// `gfx-62n`: a scene that moved refits; a scene that changed rebuilds.
///
///     flutter test test/bvh_refit_test.dart
///
/// **What this row is actually about.** The tree was rebuilt whenever anything
/// moved, which is 23 ms on 50 000 meshes — a figure no frame can absorb, and
/// the reason the threshold for using a tree at all sat at 2048. A refit keeps
/// the partition and recomputes the boxes bottom up, one linear pass, and the
/// cull it feeds reaches the same answer because a node's box still encloses
/// everything beneath it.
///
/// Three claims, and the third is the one that lets the other two be believed:
/// a frame where only transforms changed performs no rebuild; a scene of a few
/// hundred meshes goes through the tree at all; and whichever path a frame
/// takes, the set of meshes drawn is the same.
library;

import 'dart:math' as math;

import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_core/src/engine/render/material.dart';
import 'package:flutter3d_core/src/engine/render/render_list.dart';
import 'package:flutter3d_core/src/engine/render/render_view.dart';
import 'package:flutter3d_core/src/engine/scene/scene_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// A grid of cubes, deterministic so a failure reproduces.
Scene gridScene(int count, {double spacing = 3.0}) {
  final scene = Scene();
  final side = math.sqrt(count).ceil();
  final mesh = CpuMesh(CuboidShape().build());
  for (var i = 0; i < count; i++) {
    final x = (i % side) - side / 2;
    final z = (i ~/ side) - side / 2;
    scene
        .add(MeshNode(mesh, Material(), name: 'cube $i'))
        .setPosition(x * spacing, ((i * 7) % 5) - 2.0, z * spacing);
  }
  return scene;
}

/// The names a render list ended up holding.
Set<String> drawn(RenderList list) => <String>{
  for (var i = 0; i < list.length; i++) list.itemAt(i).requireNode.name!,
};

/// Builds [list] for [scene] through [camera].
void buildFor(RenderList list, Scene scene, CameraNode camera) => list.build(
  scene,
  RenderView(camera: camera),
  viewMatrix: camera.viewMatrix,
  frustum: Frustum.matrix(camera.viewProjection(1.0)),
);

CameraNode cameraFor(Scene scene, {double distance = 60.0}) {
  final camera = scene.add(CameraNode())
    ..setPosition(0.0, 25.0, distance)
    ..lookAt(Vector3.zero());
  return camera;
}

void main() {
  test('a few hundred meshes go through the tree', () {
    // The threshold is 256 rather than the hundred the row asked for, and the
    // benchmark on `RenderList.defaultBvhThreshold` says why: at 128 the plain
    // loop still wins both the everything-visible and the tenth-visible case.
    // What the row wanted is that a scene need not be enormous to get a tree,
    // and eight times smaller than before is that.
    expect(RenderList.defaultBvhThreshold, lessThan(512));

    final scene = gridScene(RenderList.defaultBvhThreshold + 20);
    final list = RenderList();
    buildFor(list, scene, cameraFor(scene));

    expect(list.usedBvh, isTrue);
    expect(list.bvh.rebuildCount, 1);
  });

  test('a frame where only transforms changed performs no rebuild', () {
    // **The row's own acceptance.** Twenty frames of a moving scene used to be
    // twenty rebuilds; they are one build and nineteen refits.
    final scene = gridScene(400);
    final camera = cameraFor(scene);
    final list = RenderList();
    final movers = scene.meshes.take(40).toList(growable: false);

    buildFor(list, scene, camera);
    expect(list.bvh.rebuildCount, 1);

    for (var frame = 0; frame < 20; frame++) {
      for (var i = 0; i < movers.length; i++) {
        movers[i].translate(0.0, math.sin((frame + i) * 0.3) * 0.05, 0.0);
      }
      buildFor(list, scene, camera);
    }

    expect(
      list.bvh.rebuildCount,
      1,
      reason: 'a transform that moved forced the whole tree to be rebuilt',
    );
    expect(list.bvh.refitCount, greaterThan(0));
  });

  test('a frame where nothing was touched does neither', () {
    // The other half, and the one that makes the tree affordable at all: the
    // render list used to repack every sphere each frame just to discover
    // whether anything had moved, which is a full pass over every mesh and
    // costs as much as the cull it is meant to replace.
    final scene = gridScene(400);
    final camera = cameraFor(scene);
    final list = RenderList();

    buildFor(list, scene, camera);
    final refitsAfterFirst = list.bvh.refitCount;

    for (var frame = 0; frame < 10; frame++) {
      buildFor(list, scene, camera);
    }

    expect(list.bvh.rebuildCount, 1);
    expect(list.bvh.refitCount, refitsAfterFirst);
  });

  test('adding a mesh rebuilds, because the partition cannot absorb it', () {
    final scene = gridScene(400);
    final camera = cameraFor(scene);
    final list = RenderList();

    buildFor(list, scene, camera);
    expect(list.bvh.rebuildCount, 1);

    scene
        .add(MeshNode(CpuMesh(CuboidShape().build()), Material(), name: 'late'))
        .setPosition(0.0, 0.0, 0.0);
    buildFor(list, scene, camera);

    expect(list.bvh.rebuildCount, 2);
    expect(drawn(list), contains('late'));
  });

  test('the tree and the loop draw the same meshes, before and after a move', () {
    // **The claim that makes the other three safe.** A refit that got the boxes
    // wrong would still be fast and would still report no rebuilds; what it
    // could not do is agree with the loop.
    //
    // Which path the second pair takes is left open on purpose, and the first
    // draft of this test got it wrong by asserting a refit: a quarter of the
    // scene moving a hundred and forty units is exactly the drift
    // `SceneBvh.rebuildAbove` exists to catch, so it rebuilds. The claim here
    // is that both paths answer the same, whichever one the tree picks.
    final scene = gridScene(400);
    final camera = cameraFor(scene);

    final tree = RenderList()..bvhThreshold = 0;
    final loop = RenderList()..bvhThreshold = 1 << 30;

    buildFor(tree, scene, camera);
    buildFor(loop, scene, camera);
    expect(tree.usedBvh, isTrue);
    expect(loop.usedBvh, isFalse);
    expect(drawn(tree), drawn(loop));
    expect(drawn(tree), isNotEmpty);

    // Now move a quarter of the scene a long way — far enough that meshes leave
    // the frustum and others enter it, so the answer has to actually change.
    for (var i = 0; i < scene.meshes.length; i += 4) {
      scene.meshes[i].translate(0.0, 0.0, -140.0);
    }

    buildFor(tree, scene, camera);
    buildFor(loop, scene, camera);
    expect(drawn(tree), drawn(loop));
  });

  test(
    'a scene that drifts far enough is rebuilt rather than refitted forever',
    () {
      // A refit keeps the partition, so objects that wander apart leave leaves
      // that overlap everything and reject nothing. `SceneBvh.rebuildAbove` is
      // where that is caught: when the summed node area has doubled, the tree is
      // worth rebuilding. Scattering the scene across a thousand units is well
      // past that.
      final scene = gridScene(400);
      final camera = cameraFor(scene);
      final list = RenderList();
      final random = math.Random(20260918);

      buildFor(list, scene, camera);
      expect(list.bvh.rebuildCount, 1);

      for (final node in scene.meshes) {
        node.translate(
          random.nextDouble() * 2000.0 - 1000.0,
          random.nextDouble() * 2000.0 - 1000.0,
          random.nextDouble() * 2000.0 - 1000.0,
        );
      }
      buildFor(list, scene, camera);

      expect(
        list.bvh.rebuildCount,
        2,
        reason: 'the tree stopped separating anything and nothing noticed',
      );
    },
  );
}
