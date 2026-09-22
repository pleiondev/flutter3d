/// `tut-21`: `buildSkeleton`'s own `meshWorld` parameter — a real bug `tut-10`
/// found and left open rather than fixed (`doc/modeler-tutorial-gaps.md`'s own
/// row calls it "a real, separate latent bug ... worth its own row").
///
/// Every marker `buildSkeleton` reads is a world-space pick (a screen-to-world
/// raycast in `autorig_markers.dart`, or the identical world-space scaling
/// `case4_scenario.dart`/`rig_pipeline_mcp_test.dart` both use headlessly),
/// but every consumer of the [ProjectSkeleton] it returns — the live
/// viewport's own GPU pipeline (`SceneSync`/`Skeleton.update`, whose own doc
/// comment states the convention outright), the shadow and object-pick
/// passes, and `render_project.dart`'s headless picture alike — expects
/// [ProjectSkeleton.inverseBindMatrices] in the glTF convention: a vertex's
/// own *local* (mesh-object) space, undone into a joint's own local space at
/// bind time. Before this fix, `buildSkeleton` instead assumed the mesh
/// object's own world transform was the identity, which is silently right
/// for a rig built on a from-scratch primitive and silently wrong for
/// anything imported with a scale or an axis swap — `RobotExpressive.glb`'s
/// own "Torso" among them, confirmed directly: a ~100x scale and an axis
/// swap, both from the file's own node hierarchy.
///
/// This file drives the *real* engine formula — `flutter3d_core`'s own
/// `Skeleton.update`, not a reimplementation of it — against a rig built
/// through a genuinely non-identity `meshWorld`, mirroring that real file's
/// own shape rather than a synthetic case nobody would ship, and checks a
/// posed vertex lands at the *correct world position*, not merely that
/// nothing throws. Every other `buildSkeleton` call in this package's own
/// test suite (`rig_template_test.dart`, `retarget_test.dart`) uses an
/// implicit identity `meshWorld` — the reason none of them caught this
/// before, and why this file exists beside them rather than folded in.
///
///     dart test test/rig_bind_convention_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/src/engine/scene/scene_node.dart';
import 'package:flutter3d_core/src/engine/scene/skeleton.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

final Aabb3 _bounds = Aabb3.minMax(Vector3(-2, -2, -2), Vector3(2, 3, 2));

final Map<String, Vector3> _markers = <String, Vector3>{
  'hips': Vector3(0, 1.0, 0),
  'spine': Vector3(0, 1.2, 0),
  'chest': Vector3(0, 1.4, 0),
  'neck': Vector3(0, 1.6, 0),
  'head': Vector3(0, 1.75, 0),
  'leftShoulder': Vector3(0.2, 1.4, 0),
  'leftElbow': Vector3(0.5, 1.4, 0),
  'leftWrist': Vector3(0.8, 1.4, 0),
  'leftHip': Vector3(0.1, 1.0, 0),
  'leftKnee': Vector3(0.1, 0.5, 0),
  'leftAnkle': Vector3(0.1, 0.05, 0),
};

/// A real engine [Skeleton], built over real [SceneNode]s laid out exactly
/// the way [BuiltRig.objects]' own doc comment promises — a parent always
/// earlier in the list than its child, translation only — the same shape
/// `SceneSync._syncSkeletons` builds for the live viewport.
Skeleton _engineSkeletonOf(BuiltRig rig) {
  final Map<int, SceneNode> nodeOf = <int, SceneNode>{};
  for (final ModelObject object in rig.objects) {
    final SceneNode node = SceneNode(name: object.name)
      ..setPositionFrom(object.transform.getTranslation());
    final int? parentId = object.parent;
    if (parentId != null) nodeOf[parentId]!.add(node);
    nodeOf[object.id] = node;
  }
  return Skeleton(
    joints: <SceneNode>[for (final id in rig.skeleton.joints) nodeOf[id]!],
    inverseBindMatrices: rig.skeleton.inverseBindMatrices,
  );
}

/// [skeleton.matrices]' own joint [index], read back as a [Matrix4] — the
/// same "read the packed array the way the shader would"
/// `packages/flutter3d/test/skinning_test.dart`'s own `jointMatrix` does.
Matrix4 _jointMatrix(Skeleton skeleton, int index) {
  final Float32List storage = Float32List(16);
  for (var e = 0; e < 16; e++) {
    storage[e] = skeleton.matrices[index * 16 + e];
  }
  return Matrix4.fromFloat32List(storage);
}

/// The world position a vertex at [localVertex] (in the mesh object's own
/// local space) lands at once [skeleton] skins it fully onto joint
/// [jointIndex] and the renderer applies [meshWorld] again — the same two
/// steps `renderer_mesh_encode.dart`'s own vertex shader performs, redone
/// here on the CPU so the assertion is a number rather than a picture.
Vector3 _skinnedWorldPosition(
  Skeleton skeleton,
  int jointIndex,
  Matrix4 meshWorld,
  Vector3 localVertex,
) {
  final Matrix4 jointMatrix = _jointMatrix(skeleton, jointIndex);
  return meshWorld.transformed3(
    jointMatrix.transformed3(Vector3.copy(localVertex)),
  );
}

void main() {
  test('a vertex bound to a joint lands at the right world position under a '
      "genuinely non-identity mesh transform (scale + axis swap, mirroring "
      "RobotExpressive.glb's own real shape)", () {
    // ~100x scale and a 90-degree axis swap — the two real distortions
    // this row's own fix (and `render_project.dart`'s doc comment) names
    // for that file, plus an arbitrary translation so no axis is special.
    final Matrix4 meshWorld = Matrix4.compose(
      Vector3(3, -1, 2),
      Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2),
      Vector3.all(100.0),
    );

    final BuiltRig rig = buildSkeleton(
      RigTemplate.humanoid,
      _markers,
      bounds: _bounds,
      firstObjectId: 1,
      meshWorld: meshWorld,
    );
    final Skeleton skeleton = _engineSkeletonOf(rig);

    final int wristId = rig.objects
        .firstWhere((ModelObject o) => o.name == 'leftWrist')
        .id;
    final int wristIndex = rig.skeleton.joints.indexOf(wristId);
    expect(wristIndex, greaterThanOrEqualTo(0));

    // A vertex placed, in the mesh's own local space, so that at bind
    // time it sits exactly on the wrist marker's own world position —
    // `inverse(meshWorld) * worldPosition`, the mesh-local pick a real
    // weight-paint bind would leave a fully-weighted vertex at.
    final Matrix4 invMeshWorld = Matrix4.copy(meshWorld)..invert();
    final Vector3 localVertex = invMeshWorld.transformed3(
      Vector3.copy(_markers['leftWrist']!),
    );

    skeleton.update(meshWorld);
    final Vector3 atRest = _skinnedWorldPosition(
      skeleton,
      wristIndex,
      meshWorld,
      localVertex,
    );

    // The bug this row fixes: without `meshWorld` folded into
    // `inverseBindMatrices`, the GPU formula's `inverse(meshWorld)` and
    // `jointWorld * inverse(jointWorld)` cancel each other out and this
    // lands at `localVertex` itself — about a hundredth of the marker's
    // own position at this scale, the exact "torso collapses to about
    // 1% of its real size" this row's own fix describes.
    expect(atRest.x, closeTo(_markers['leftWrist']!.x, 1e-4));
    expect(atRest.y, closeTo(_markers['leftWrist']!.y, 1e-4));
    expect(atRest.z, closeTo(_markers['leftWrist']!.z, 1e-4));

    // Posed, not just at bind: move the wrist joint's own node and check
    // the skinned vertex follows it by the same delta — every joint in
    // this rig is a pure translation with no rotated ancestor, so a
    // local move is a world move — the "posed GPU-formula result", not
    // only a bind-pose no-op.
    final SceneNode wristNode = skeleton.joints[wristIndex];
    final Vector3 delta = Vector3(0.3, -0.15, 0.4);
    wristNode.setPositionFrom(wristNode.readPosition() + delta);
    skeleton.update(meshWorld);

    final Vector3 posed = _skinnedWorldPosition(
      skeleton,
      wristIndex,
      meshWorld,
      localVertex,
    );
    final Vector3 expected = _markers['leftWrist']! + delta;
    expect(posed.x, closeTo(expected.x, 1e-4));
    expect(posed.y, closeTo(expected.y, 1e-4));
    expect(posed.z, closeTo(expected.z, 1e-4));
  });
}
