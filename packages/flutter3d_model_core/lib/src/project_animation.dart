/// A skeleton and a clip, as a project holds them — `anim-03`'s own row.
///
/// **Joints and tracks name a [ModelObject] by id, not by node index.** Every
/// other project-level reference already keeps this contract — a material
/// slot, a parent — and the reason repeats here: an id is stable for the
/// life of the object and a node index is not even stable across one
/// export, since [ProjectModelDocument.of] numbers nodes by walking the
/// project fresh every call. A skeleton or a clip that named an index would
/// point at a different joint the moment an unrelated object earlier in the
/// list was deleted.
library;

import 'dart:math' as math;

import 'package:flutter3d_core/formats.dart';
import 'package:vector_math/vector_math.dart';

/// A skinned skeleton: which objects are joints, and how each undoes the
/// bind pose — the project-side [ModelSkin], addressed by object id where
/// that one is addressed by node index.
final class ProjectSkeleton {
  ProjectSkeleton({
    required List<int> joints,
    required this.inverseBindMatrices,
    this.skeletonRoot,
    this.name,
    List<IkConstraint> constraints = const <IkConstraint>[],
  }) : joints = List.unmodifiable(joints),
       constraints = List.unmodifiable(constraints) {
    if (inverseBindMatrices.length != joints.length) {
      throw ArgumentError(
        'ProjectSkeleton "${name ?? 'unnamed'}" has ${joints.length} joints '
        'but ${inverseBindMatrices.length} inverse bind matrices.',
      );
    }
  }

  final String? name;

  /// [ModelObject.id]s, in the order the vertex attribute addresses them.
  final List<int> joints;

  /// One per joint — see [ModelSkin.inverseBindMatrices] for what it
  /// undoes; the meaning is identical, only the joint list's own addressing
  /// differs.
  final List<Matrix4> inverseBindMatrices;

  /// The object the skeleton hangs from, by id, when the source named one.
  final int? skeletonRoot;

  /// Two-bone solves applied after FK — `anim-15`'s own row. Empty for
  /// almost every skeleton, the ordinary case until a rig actually needs
  /// one.
  final List<IkConstraint> constraints;

  int get jointCount => joints.length;

  /// [this], with named fields replaced.
  ProjectSkeleton copyWith({
    List<int>? joints,
    List<Matrix4>? inverseBindMatrices,
    int? skeletonRoot,
    bool clearSkeletonRoot = false,
    String? name,
    List<IkConstraint>? constraints,
  }) => ProjectSkeleton(
    joints: joints ?? this.joints,
    inverseBindMatrices: inverseBindMatrices ?? this.inverseBindMatrices,
    skeletonRoot: clearSkeletonRoot
        ? null
        : (skeletonRoot ?? this.skeletonRoot),
    name: name ?? this.name,
    constraints: constraints ?? this.constraints,
  );

  @override
  String toString() =>
      'ProjectSkeleton(${name ?? 'unnamed'}, ${joints.length} joints)';
}

/// A two-bone IK solve, root → mid → effector, bent after FK so the
/// effector reaches [target] — `anim-15`'s own row, `IkConstraint` in
/// `ProjectSkeleton.constraints`.
///
/// **Three joints, not a general chain.** `FabrikIk` (`anim-14`, engine
/// package) solves a chain of any length; this row's own acceptance only
/// ever exercises the textbook two-bone case — an arm or a leg — and a
/// general N-bone project-level solver is a bigger thing this row does not
/// ask for. [rootJointId], [midJointId] and [effectorJointId] are
/// [ModelObject.id]s, the same addressing [ProjectSkeleton.joints] and
/// [ProjectTrack.objectId] already use; [midJointId] is expected to be
/// [rootJointId]'s own child and [effectorJointId] [midJointId]'s, the
/// ordinary shape of an upper-arm/forearm or thigh/shin pair.
final class IkConstraint {
  const IkConstraint({
    required this.rootJointId,
    required this.midJointId,
    required this.effectorJointId,
    required this.target,
    required this.pole,
  });

  final int rootJointId;
  final int midJointId;
  final int effectorJointId;

  /// Where [effectorJointId] should land, in the space [rootJointId]'s own
  /// ancestors share.
  final Vector3 target;

  /// A point the middle joint bends toward — the only input that decides
  /// which of the two ways a two-bone chain can fold, the same role
  /// `TwoBoneIk.solve`'s own `pole` plays in the engine.
  final Vector3 pole;

  @override
  String toString() =>
      'IkConstraint($rootJointId → $midJointId → $effectorJointId → $target)';
}

/// One joint turned to face [target], within the angles it is allowed —
/// `anim-31n`'s other half, and the reason that row names a look-at
/// alongside the two-bone solve: a hero who plants a foot on a step also
/// has to follow something with their head, and a head that follows
/// without a limit turns to face its own back.
///
/// **The limits are measured against the joint's own rest pose, in its
/// parent's space.** That is what a neck limit means when somebody says
/// it: sixty degrees of yaw is sixty degrees away from where the head sits
/// when the character looks straight ahead, and it stays sixty degrees
/// when the character turns, because the whole reference frame turns with
/// the chest. Measuring against the world instead would give a character
/// who can look left only while facing north.
///
/// [forward] and [up] say which of the joint's own local axes is its face
/// and which is the top of its head. Both are required, and deliberately:
/// this is the one thing that cannot be guessed — glTF rigs out of
/// different tools disagree about it — and a default would aim the ear
/// while looking like it worked.
///
/// The angles, by contrast, default to `pi`, which is no limit: a caller
/// who has not decided what a joint may do should get the unconstrained
/// look-at they asked for rather than a limit somebody invented.
final class LookAtConstraint {
  const LookAtConstraint({
    required this.jointId,
    required this.target,
    required this.forward,
    required this.up,
    this.maxYaw = math.pi,
    this.maxPitch = math.pi,
  });

  /// [ModelObject.id] of the joint that turns.
  final int jointId;

  /// What it looks at, in the space [jointId]'s own ancestors share — the
  /// same space [IkConstraint.target] is in.
  final Vector3 target;

  /// [jointId]'s own local axis that points out of its face.
  final Vector3 forward;

  /// [jointId]'s own local axis that points out of the top of its head.
  /// Only the component perpendicular to [forward] is used, so an `up`
  /// that is not exactly square to the face is corrected rather than
  /// refused.
  final Vector3 up;

  /// How far the joint may turn left or right of its rest facing, in
  /// radians. `pi` — the default — is no limit at all.
  final double maxYaw;

  /// How far it may tilt up or down, in radians.
  final double maxPitch;

  @override
  String toString() =>
      'LookAtConstraint($jointId → $target, '
      '±${maxYaw.toStringAsFixed(2)} yaw, ±${maxPitch.toStringAsFixed(2)} '
      'pitch)';
}

/// One [AnimationTrack], retargeted from a node index onto an object id.
///
/// A wrapper rather than a copy of [AnimationTrack]'s own fields: sampling a
/// track is the same arithmetic whichever kind of index put it there, and
/// [AnimationTrack.sample] already does it. [track]'s own `nodeIndex` is
/// whatever the source document happened to carry it as and is not read
/// here — [objectId] is the only addressing this class honours.
final class ProjectTrack {
  const ProjectTrack({required this.objectId, required this.track});

  /// [ModelObject.id] this track drives.
  final int objectId;

  final AnimationTrack track;
}

/// A named set of [ProjectTrack]s that play together — the project-side
/// [AnimationClip].
final class ProjectClip {
  const ProjectClip({this.name, required this.tracks, this.extras});

  final String? name;
  final List<ProjectTrack> tracks;

  /// glTF's own `extras` on this animation, carried opaquely — see
  /// [ModelNode.extras] for what that means and why.
  final Map<String, Object?>? extras;

  bool get isEmpty => tracks.isEmpty;

  @override
  String toString() =>
      'ProjectClip(${name ?? 'unnamed'}, ${tracks.length} tracks)';
}
