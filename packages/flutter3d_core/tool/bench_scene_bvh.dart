// ignore_for_file: avoid_print — a command-line benchmark whose whole output is
// stdout.

/// What building a render list costs with the tree and without it — `gfx-62n`.
///
///     dart compile exe tool/bench_scene_bvh.dart -o /tmp/bench && /tmp/bench
///
/// **The question this answers is where `RenderList.bvhThreshold` belongs.**
/// The old figure was 2048, and it was that high because a rebuild is the
/// expensive part and the tree was rebuilt whenever anything moved. With a
/// refit in place the per-frame cost of keeping the tree is one linear pass, so
/// the threshold is no longer defending against the build — it is only
/// defending against traversal being slower than a short loop.
///
/// **It builds the real render list rather than testing bare spheres**, and
/// that is the point. A mesh the tree never visits costs nothing; a mesh the
/// linear pass reaches costs the visibility flags, the layer mask, the index
/// count, a bounds refresh and a frustum test before it can be rejected. A
/// benchmark that compares two sphere tests measures neither of those and
/// flatters the loop.
///
/// Two visibilities, because they are the two different answers. Everything on
/// screen is the tree's worst case: it rejects nothing and adds traversal on
/// top of the same per-mesh work. A tenth on screen is the ordinary case, and
/// the one a tree exists for.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_core/src/engine/render/material.dart';
import 'package:flutter3d_core/src/engine/render/render_list.dart';
import 'package:flutter3d_core/src/engine/render/render_view.dart';
import 'package:flutter3d_core/src/engine/scene/scene_graph.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// A cube of [count] unit cubes on a grid, [spacing] apart.
Scene gridScene(int count, double spacing) {
  final scene = Scene();
  final side = pow(count, 1 / 3).ceil();
  final mesh = CpuMesh(CuboidShape().build());
  final material = Material();
  for (var i = 0; i < count; i++) {
    final x = (i % side) - side / 2;
    final y = ((i ~/ side) % side) - side / 2;
    final z = (i ~/ (side * side)) - side / 2;
    scene
        .add(MeshNode(mesh, material, name: 'cube $i'))
        .setPosition(x * spacing, y * spacing, z * spacing);
  }
  return scene;
}

double microseconds(int iterations, void Function() body) {
  body();
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    body();
  }
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds / iterations;
}

/// A camera at [eye] looking at [target], with [fov] degrees across.
CameraNode cameraAt(Scene scene, Vector3 eye, Vector3 target, double fov) {
  final camera = scene.add(
    CameraNode()
      ..projection = PerspectiveProjection(
        fovYRadians: fov * pi / 180.0,
        near: 0.5,
        far: 100000.0,
      ),
  );
  camera
    ..setPosition(eye.x, eye.y, eye.z)
    ..lookAt(target);
  return camera;
}

void main() {
  print('every figure is microseconds per frame');
  print('');

  for (final count in <int>[64, 128, 256, 1024, 4096, 50000]) {
    const spacing = 4.0;
    final scene = gridScene(count, spacing);
    final side = pow(count, 1 / 3).ceil() * spacing;

    print('--- $count meshes ------------------------------------');

    // What keeping the tree costs, separate from what querying it saves. The
    // stamp changes every call, which is the frame where something moved; a
    // static frame pays neither figure, because `refresh` returns at once.
    final spheres = ensureSphereCapacity(Float32List(0), scene.meshes.length);
    final tree = SceneBvh()
      ..refresh(spheres, count, packSceneSpheres(scene.meshes, spheres));
    final rebuild = microseconds(10, () {
      SceneBvh().refresh(spheres, count, 1);
    });
    var stamp = 2;
    final refit = microseconds(20, () {
      tree.refresh(spheres, count, stamp++);
    });
    final pack = microseconds(30, () {
      packSceneSpheres(scene.meshes, spheres);
    });
    print(
      '  keeping it: rebuild ${rebuild.toStringAsFixed(1)} us   '
      'refit ${refit.toStringAsFixed(1)} us   '
      '(${(rebuild / refit).toStringAsFixed(0)}x)   '
      'pack ${pack.toStringAsFixed(1)} us',
    );

    final cases = <String, CameraNode>{
      'all': cameraAt(
        scene,
        Vector3(0.0, 0.0, side * 2.0),
        Vector3.zero(),
        90.0,
      ),
      'tenth': cameraAt(
        scene,
        Vector3(0.0, 0.0, side * 0.55),
        Vector3.zero(),
        30.0,
      ),
    };

    for (final entry in cases.entries) {
      final camera = entry.value;
      final view = RenderView(camera: camera);
      final viewMatrix = camera.viewMatrix;
      final frustum = Frustum.matrix(camera.viewProjection(1.0));

      // Two lists rather than one with the threshold moved between runs, so
      // neither run inherits the other's warmed pools.
      final loop = RenderList()..bvhThreshold = count + 1;
      final tree = RenderList()..bvhThreshold = 0;

      void build(RenderList list) =>
          list.build(scene, view, viewMatrix: viewMatrix, frustum: frustum);

      // Enough repeats that a small scene is not timed against the clock's own
      // granularity: at 64 meshes a frame is two microseconds, and thirty of
      // those is a measurement of the Stopwatch.
      final repeats = max(30, 2000000 ~/ count);
      final loopTime = microseconds(repeats, () => build(loop));
      final treeTime = microseconds(repeats, () => build(tree));

      if (loop.length != tree.length) {
        print('  ${entry.key}: MISMATCH ${loop.length} vs ${tree.length}');
        continue;
      }

      print(
        '  ${entry.key.padRight(6)} ${loop.length} drawn   '
        'linear ${loopTime.toStringAsFixed(1)} us   '
        'tree ${treeTime.toStringAsFixed(1)} us   '
        '${treeTime < loopTime ? 'tree wins' : 'linear wins'}',
      );
    }
    print('');
  }
}
