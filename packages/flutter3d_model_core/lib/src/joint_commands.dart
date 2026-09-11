/// The commands over one skeleton's own joint list — `anim-29`'s own row,
/// the part of `doc-26` that `anim-03` (the types) and `anim-04` (keyframe
/// editing) do not cover.
///
/// A `part` of `command.dart` for the reason every other command file
/// gives: [ModelCommand] is sealed, and a journal writer's exhaustive
/// `switch` is only exhaustive if the compiler can see every case inside
/// one library.
///
/// **`SetRestPose` reads `worldTransformOf`, added alongside it.** Setting
/// a joint's rest pose in world space and recomputing its inverse bind
/// matrix both need a joint's own *world* transform — its object's own
/// transform composed out through every ancestor — which nothing in this
/// package computed before this row.
///
/// **What is still not here: `MirrorJoints`.** Reflecting a rest pose
/// across an axis needs mirroring a full rigid transform — the rotation
/// along with the position, which flips handedness and is not simply
/// negating a component — and nothing in this row's own acceptance line
/// tests it (that line is entirely about `RemoveJoint`): built when a real
/// caller needs it rather than shipped now on the strength of arithmetic
/// worked out but never run against a case that would catch it wrong.
part of 'command.dart';

/// The skeleton at [skeletonIndex] in [project], or the sentence to refuse
/// with.
({ProjectSkeleton? skeleton, String? refused}) _skeletonTarget(
  ModelProject project,
  int skeletonIndex,
) {
  if (skeletonIndex < 0 || skeletonIndex >= project.skeletons.length) {
    return (skeleton: null, refused: 'there is no skeleton $skeletonIndex');
  }
  return (skeleton: project.skeletons[skeletonIndex], refused: null);
}

ModelProject _withSkeleton(ModelProject project, int index, ProjectSkeleton skeleton) {
  final skeletons = List<ProjectSkeleton>.of(project.skeletons)..[index] = skeleton;
  return project.copyWith(skeletons: skeletons);
}

/// Adds [objectId] to skeleton [skeletonIndex]'s own joint list, at
/// [inverseBindMatrix] (identity when the object's own bind pose is
/// already its rest pose).
final class AddJoint extends ModelCommand {
  const AddJoint({required this.skeletonIndex, required this.objectId, this.inverseBindMatrix});

  final int skeletonIndex;
  final int objectId;
  final Matrix4? inverseBindMatrix;

  @override
  String get name => 'addJoint';

  @override
  String get says => 'add a joint';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'skeletonIndex': skeletonIndex,
    'objectId': objectId,
    if (inverseBindMatrix != null) 'inverseBindMatrix': inverseBindMatrix!.storage,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:skeleton, :refused) = _skeletonTarget(project, skeletonIndex);
    if (skeleton == null) return Outcome.refused(refused!);
    if (project[objectId] == null) {
      return Outcome.refused('there is no object $objectId');
    }
    if (skeleton.joints.contains(objectId)) {
      return Outcome.refused('object $objectId is already a joint of this skeleton');
    }
    final next = skeleton.copyWith(
      joints: <int>[...skeleton.joints, objectId],
      inverseBindMatrices: <Matrix4>[
        ...skeleton.inverseBindMatrices,
        inverseBindMatrix ?? Matrix4.identity(),
      ],
    );
    return Outcome.done(_withSkeleton(project, skeletonIndex, next));
  }
}

/// Removes [jointIndex] from skeleton [skeletonIndex], reassigning every
/// vertex weight it carried to the removed joint's own parent joint (or
/// dropping it, renormalized among what is left, when the parent is not
/// itself one of this skeleton's joints) and shifting every weight naming a
/// later joint index down by one.
final class RemoveJoint extends ModelCommand {
  const RemoveJoint({required this.skeletonIndex, required this.jointIndex});

  final int skeletonIndex;
  final int jointIndex;

  @override
  String get name => 'removeJoint';

  @override
  String get says => 'remove a joint';

  @override
  Map<String, Object?> get arguments =>
      <String, Object?>{'skeletonIndex': skeletonIndex, 'jointIndex': jointIndex};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:skeleton, :refused) = _skeletonTarget(project, skeletonIndex);
    if (skeleton == null) return Outcome.refused(refused!);
    if (jointIndex < 0 || jointIndex >= skeleton.jointCount) {
      return Outcome.refused(
        'skeleton $skeletonIndex has ${skeleton.jointCount} joints; '
        '$jointIndex is not one of them',
      );
    }

    final removedObjectId = skeleton.joints[jointIndex];
    final removedObject = project[removedObjectId];
    int? parentJointIndex;
    if (removedObject?.parent != null) {
      final parentIndex = skeleton.joints.indexOf(removedObject!.parent!);
      if (parentIndex >= 0) parentJointIndex = parentIndex;
    }

    // Each mesh gets its own journal step, the way every mesh command in
    // this package already opens one before writing — see `mesh_commands
    // .dart`. **`Outcome` tracks one `meshTouched`, not several**: a
    // skeleton bound to more than one skinned object edits every one of
    // their meshes correctly here, but undo can only roll back the last
    // one `Outcome.done` names below. The ordinary case — one character,
    // one skinned mesh — is unaffected; a skeleton shared by several
    // meshes is the case this falls short on, recorded rather than hidden.
    var next = project;
    EditMesh? lastTouched;
    for (final object in project.objects) {
      if (object.skeletonIndex != skeletonIndex) continue;
      if (object.geometry case EditedGeometry(:final mesh)) {
        var wrote = false;
        for (var v = 0; v < mesh.vertexSlotCount; v++) {
          if (!mesh.isVertexAlive(v)) continue;
          final pairs = weightsOf(mesh, v);
          if (pairs.every((p) => p.joint != jointIndex)) continue;
          if (!wrote) {
            mesh.beginStep();
            wrote = true;
          }
          final removedWeight = pairs
              .where((p) => p.joint == jointIndex)
              .fold<double>(0, (sum, p) => sum + p.weight);
          final reassigned = <WeightPair>[
            for (final p in pairs)
              if (p.joint != jointIndex)
                WeightPair(
                  p.joint > jointIndex ? p.joint - 1 : p.joint,
                  p.joint == parentJointIndex ? p.weight + removedWeight : p.weight,
                ),
            if (parentJointIndex != null && !pairs.any((p) => p.joint == parentJointIndex))
              WeightPair(
                parentJointIndex > jointIndex ? parentJointIndex - 1 : parentJointIndex,
                removedWeight,
              ),
          ];
          mesh.setSkin(v, toVertexAttributes(normalizeWeights(reassigned)));
        }
        if (wrote) {
          mesh.endStep();
          lastTouched = mesh;
        }
      }
    }

    final joints = List<int>.of(skeleton.joints)..removeAt(jointIndex);
    final matrices = List<Matrix4>.of(skeleton.inverseBindMatrices)..removeAt(jointIndex);
    next = _withSkeleton(
      next,
      skeletonIndex,
      skeleton.copyWith(joints: joints, inverseBindMatrices: matrices),
    );
    return Outcome.done(next, meshTouched: lastTouched);
  }
}

/// Renames the object at joint [jointIndex] of skeleton [skeletonIndex] —
/// [Rename]'s own refusal for a blank name, reached through a skeleton's
/// own joint index rather than an id directly.
final class RenameJoint extends ModelCommand {
  const RenameJoint({required this.skeletonIndex, required this.jointIndex, required this.to});

  final int skeletonIndex;
  final int jointIndex;
  final String to;

  @override
  String get name => 'renameJoint';

  @override
  String get says => 'rename a joint to "$to"';

  @override
  Map<String, Object?> get arguments =>
      <String, Object?>{'skeletonIndex': skeletonIndex, 'jointIndex': jointIndex, 'to': to};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:skeleton, :refused) = _skeletonTarget(project, skeletonIndex);
    if (skeleton == null) return Outcome.refused(refused!);
    if (jointIndex < 0 || jointIndex >= skeleton.jointCount) {
      return Outcome.refused(
        'skeleton $skeletonIndex has ${skeleton.jointCount} joints; '
        '$jointIndex is not one of them',
      );
    }
    return Rename(id: skeleton.joints[jointIndex], to: to).apply(project, selection);
  }
}

/// Reparents the object at joint [jointIndex] of skeleton [skeletonIndex]
/// under [to] — an object id, which need not itself be a joint of this
/// skeleton (a hand may be parented under a wrist bone that is itself not
/// skinned, for instance). A thin wrapper over [SetParent], addressed
/// through a skeleton's own joint index rather than an id directly — the
/// cycle check and the refusals are [SetParent]'s own, not repeated here.
final class ReparentJoint extends ModelCommand {
  const ReparentJoint({required this.skeletonIndex, required this.jointIndex, required this.to});

  final int skeletonIndex;
  final int jointIndex;
  final int? to;

  @override
  String get name => 'reparentJoint';

  @override
  String get says => 'reparent a joint';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'skeletonIndex': skeletonIndex,
    'jointIndex': jointIndex,
    'to': to,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:skeleton, :refused) = _skeletonTarget(project, skeletonIndex);
    if (skeleton == null) return Outcome.refused(refused!);
    if (jointIndex < 0 || jointIndex >= skeleton.jointCount) {
      return Outcome.refused(
        'skeleton $skeletonIndex has ${skeleton.jointCount} joints; '
        '$jointIndex is not one of them',
      );
    }
    final jointId = skeleton.joints[jointIndex];
    return SetParent(id: jointId, to: to).apply(project, selection);
  }
}

/// Sets joint [jointIndex] of skeleton [skeletonIndex]'s own rest pose to
/// [worldTransform] — a world-space transform, since that is the space a
/// gizmo or a "match this other bone" tool naturally has one in — and
/// recomputes both the joint object's own local transform and the
/// skeleton's own inverse bind matrix for it, "с пересчётом inverseBind",
/// the row's own words.
final class SetRestPose extends ModelCommand {
  const SetRestPose({
    required this.skeletonIndex,
    required this.jointIndex,
    required this.worldTransform,
  });

  final int skeletonIndex;
  final int jointIndex;
  final Matrix4 worldTransform;

  @override
  String get name => 'setRestPose';

  @override
  String get says => 'move a joint\'s rest pose';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'skeletonIndex': skeletonIndex,
    'jointIndex': jointIndex,
    'worldTransform': worldTransform.storage,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final (:skeleton, :refused) = _skeletonTarget(project, skeletonIndex);
    if (skeleton == null) return Outcome.refused(refused!);
    if (jointIndex < 0 || jointIndex >= skeleton.jointCount) {
      return Outcome.refused(
        'skeleton $skeletonIndex has ${skeleton.jointCount} joints; '
        '$jointIndex is not one of them',
      );
    }
    final jointId = skeleton.joints[jointIndex];
    final object = project[jointId]!;

    final parentWorld = object.parent == null
        ? Matrix4.identity()
        : worldTransformOf(project, object.parent!);
    final local = Matrix4.inverted(parentWorld)..multiply(worldTransform);

    final matrices = List<Matrix4>.of(skeleton.inverseBindMatrices)
      ..[jointIndex] = Matrix4.inverted(worldTransform);

    var next = project.withObject(object.copyWith(transform: local));
    next = _withSkeleton(
      next,
      skeletonIndex,
      skeleton.copyWith(inverseBindMatrices: matrices),
    );
    return Outcome.done(next);
  }
}
