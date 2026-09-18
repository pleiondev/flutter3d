/// `gfx-66n`: a branch outside the frustum costs one test, not one per mesh.
///
///     flutter test test/subtree_bounds_test.dart
///
/// **What it cost.** A mesh's own world box was the only bound in the engine,
/// and the cull walked the scene's flat registry, so a node holding two hundred
/// meshes — a room, a vehicle, a character — was two hundred frustum tests even
/// with the whole thing behind the camera.
///
/// **The order is the same order**, and that is the part that had to be true
/// before the walk could replace the registry loop: `SortMode.manual` and every
/// tie in the other modes fall back to the order draws were claimed in, and the
/// registry is filled by `onAttachedToScene`, which a subtree reaches in
/// pre-order. The last test here holds to that, and the forty-four golden
/// frames held to it too.
library;

import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_core/src/engine/render/material.dart';
import 'package:flutter3d_core/src/engine/render/render_list.dart';
import 'package:flutter3d_core/src/engine/render/render_view.dart';
import 'package:flutter3d_core/src/engine/scene/scene_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// A group node holding [count] cubes in a small cluster around its origin.
SceneNode _cluster(String name, int count) {
  final group = SceneNode(name: name);
  final mesh = CpuMesh(CuboidShape().build());
  for (var i = 0; i < count; i++) {
    group.add(
      MeshNode(mesh, Material(), name: '$name $i')
        ..setPosition((i % 5) - 2.0, ((i ~/ 5) % 5) - 2.0, 0.0),
    );
  }
  return group;
}

void buildFor(RenderList list, Scene scene, CameraNode camera) => list.build(
  scene,
  RenderView(camera: camera),
  viewMatrix: camera.viewMatrix,
  frustum: Frustum.matrix(camera.viewProjection(1.0)),
);

void main() {
  test('a branch behind the camera is one test, not one per mesh', () {
    // **The row's own acceptance.** Two clusters of a hundred: one in front of
    // the camera and one a long way behind it. The cull has to look at the
    // hundred it can see and at none of the hundred it cannot.
    final scene = Scene()
      ..add(_cluster('near', 100))
      ..add(_cluster('far', 100)..setPosition(0.0, 0.0, 400.0));
    final camera = scene.add(CameraNode())
      ..setPosition(0.0, 0.0, 20.0)
      ..lookAt(Vector3.zero());

    final list = RenderList();
    buildFor(list, scene, camera);

    expect(scene.meshes.length, 200);
    expect(
      list.considered,
      100,
      reason: 'the branch nobody can see was still tested mesh by mesh',
    );
    expect(list.length, 100);
  });

  test('a branch with a mesh that opted out of culling is kept whole', () {
    // A sky dome, a held weapon or an editor gizmo sets `frustumCulled` false
    // precisely because it is placed where the frustum says nothing is. One of
    // those anywhere under a branch has to keep the branch, or it disappears —
    // which is the bug a subtree bound invites and the reason `subtreeBounds`
    // carries the flag as well as the box.
    final distant = _cluster('far', 100);
    (distant.childrenView.last as MeshNode).frustumCulled = false;

    final scene = Scene()
      ..add(_cluster('near', 100))
      ..add(distant..setPosition(0.0, 0.0, 400.0));
    final camera = scene.add(CameraNode())
      ..setPosition(0.0, 0.0, 20.0)
      ..lookAt(Vector3.zero());

    final list = RenderList();
    buildFor(list, scene, camera);

    expect(
      list.considered,
      200,
      reason: 'the opted-out mesh was never reached',
    );
    expect(<String>[
      for (var i = 0; i < list.length; i++) list.itemAt(i).requireNode.name!,
    ], contains('far 99'));
  });

  test('a hidden branch costs nothing either', () {
    // `visible` is false on the group rather than on its meshes, which used to
    // mean a hundred calls to `visibleInHierarchy`, each walking to the root.
    final hidden = _cluster('hidden', 100)..visible = false;
    final scene = Scene()
      ..add(_cluster('near', 100))
      ..add(hidden);
    final camera = scene.add(CameraNode())
      ..setPosition(0.0, 0.0, 20.0)
      ..lookAt(Vector3.zero());

    final list = RenderList();
    buildFor(list, scene, camera);

    expect(list.considered, 100);
  });

  test('a branch that moves back into view comes back', () {
    // The subtree box is cached on the epoch, so this is what catches a cache
    // that never invalidates: the same scene, the same camera, one group moved.
    final group = _cluster('mover', 40)..setPosition(0.0, 0.0, 400.0);
    final scene = Scene()..add(group);
    final camera = scene.add(CameraNode())
      ..setPosition(0.0, 0.0, 20.0)
      ..lookAt(Vector3.zero());

    final list = RenderList();
    buildFor(list, scene, camera);
    expect(list.length, 0);

    group.setPosition(0.0, 0.0, 0.0);
    buildFor(list, scene, camera);
    expect(list.length, 40);
  });

  test('the walk claims draws in the order the registry holds them', () {
    // **The claim that let this land.** Every tie in every sort mode falls back
    // to the order draws were claimed in, so a walk that visited the hierarchy
    // in some other order would reshuffle equal-keyed draws — invisible in most
    // frames and not in a frame with coplanar transparent surfaces in it.
    final scene = Scene()
      ..add(_cluster('a', 20))
      ..add(_cluster('b', 20)..setPosition(8.0, 0.0, 0.0));
    final camera = scene.add(CameraNode())
      ..setPosition(0.0, 0.0, 60.0)
      ..lookAt(Vector3.zero());

    final list = RenderList();
    buildFor(list, scene, camera);

    expect(<MeshNode>[
      for (var i = 0; i < list.length; i++) list.itemAt(i).requireNode,
    ], scene.meshes);
  });

  test('a subtree that draws nothing has no bounds', () {
    // Which is not the same as an empty box at the origin: a point at the
    // origin would drag every ancestor's bound out to meet it, and a group of
    // empty transforms placed off in the distance would keep its whole branch.
    final group = SceneNode(name: 'empty')..add(SceneNode(name: 'also empty'));
    Scene().add(group);

    expect(group.subtreeBounds, isNull);
    expect(group.subtreeAlwaysDrawn, isFalse);
  });
}
