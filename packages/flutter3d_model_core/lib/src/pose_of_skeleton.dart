/// [poseOf]: a [ProjectSkeleton]'s own rest pose, as a scene-graph-free
/// [Pose] — `view-27d`'s own row, alongside `apps/flutter3d_modeler/lib/src/
/// scene_sync.dart`, which is what actually hangs a live engine `Skeleton`
/// off a project's joints. This is for anything that needs a skeleton's
/// bind-pose world matrices — a test building a [ProjectSkeleton] by hand
/// and needing its own inverse bind matrices, a caller measuring a rig
/// before there is a live `Scene` anywhere to ask — with none of that.
///
/// `flutter3d_model_core` already depends on `flutter3d_core` for
/// `render_project.dart`'s own `Scene`/`Renderer` (see that file's own doc
/// comment for the boundary this package actually keeps: the Flutter-free
/// half of the engine, never `flutter3d` or `flutter3d_cpu` themselves), and
/// [Pose] lives there too — a flat, [SceneNode]-free hierarchy of local TRS,
/// exactly what a rest pose is before anything hangs a node off it.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart' show Pose;
import 'package:vector_math/vector_math.dart';

import 'project.dart';
import 'project_animation.dart';
import 'world_transform.dart';

/// [skeleton]'s own joints, as a [Pose] holding each one's rest transform.
///
/// **[Pose.parents] indexes locally, into [skeleton.joints] itself, never
/// by object id.** A joint parented under another joint of this same
/// skeleton is recorded as that joint's own position in the list, and
/// [Pose.worldMatrices] then composes the two exactly as
/// [ModelObject.transform] would compose through a real scene, since the two
/// hierarchies agree wherever they overlap.
///
/// **A joint with no such partner is not, on that account, treated as
/// standing at the origin.** This [Pose]'s own claim is only over
/// [skeleton]'s joints — a root joint hung under some other object entirely
/// (a rig's own controller, say, itself not a joint) still has to answer for
/// whatever that ancestor contributes, so [worldTransformOf] — the same
/// walk every other joint-adjacent command in this package already
/// trusts — supplies that joint's rest transform instead of its own bare
/// [ModelObject.transform]. [Pose.worldMatrices] then comes out identical to
/// what a real [SceneNode.worldMatrix] would read off the hierarchy
/// `scene_sync.dart` builds.
///
/// A joint id [ModelProject] does not hold reads as the identity transform,
/// the same tolerance [worldTransformOf] itself has for one.
Pose poseOf(ModelProject project, ProjectSkeleton skeleton) {
  final joints = skeleton.joints;
  final localIndexOf = <int, int>{
    for (var i = 0; i < joints.length; i++) joints[i]: i,
  };

  final parents = List<int>.filled(joints.length, -1);
  final translations = Float32List(joints.length * 3);
  final rotations = Float32List(joints.length * 4);
  final scales = Float32List(joints.length * 3);

  final translation = Vector3.zero();
  final rotation = Quaternion.identity();
  final scale = Vector3.zero();

  for (var i = 0; i < joints.length; i++) {
    final ModelObject? object = project[joints[i]];
    final int? parentId = object?.parent;
    final int? parentIndex = parentId == null ? null : localIndexOf[parentId];

    final Matrix4 local;
    if (object == null) {
      local = Matrix4.identity();
    } else if (parentIndex != null) {
      parents[i] = parentIndex;
      local = object.transform;
    } else {
      local = worldTransformOf(project, object.id);
    }

    local.decompose(translation, rotation, scale);
    translations[i * 3] = translation.x;
    translations[i * 3 + 1] = translation.y;
    translations[i * 3 + 2] = translation.z;
    rotations[i * 4] = rotation.x;
    rotations[i * 4 + 1] = rotation.y;
    rotations[i * 4 + 2] = rotation.z;
    rotations[i * 4 + 3] = rotation.w;
    scales[i * 3] = scale.x;
    scales[i * 3 + 1] = scale.y;
    scales[i * 3 + 2] = scale.z;
  }

  return Pose(
    parents: parents,
    restTranslations: translations,
    restRotations: rotations,
    restScales: scales,
  );
}
