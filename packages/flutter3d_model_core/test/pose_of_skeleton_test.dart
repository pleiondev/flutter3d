/// `view-27d`'s own row: `poseOf`, a `ProjectSkeleton`'s rest transforms as
/// a scene-graph-free `Pose`.
///
///     dart test test/pose_of_skeleton_test.dart
library;

import 'package:flutter3d_core/flutter3d_core.dart' show Pose;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A joint with no mesh of its own — [localOffset] from [parent], or from
/// the origin when there is none — the same shape `ik_constraint_test.dart`'s
/// own `_joint` already builds.
ModelObject _joint(int id, {int? parent, required Vector3 localOffset}) =>
    ModelObject(
      id: id,
      name: 'joint$id',
      geometry: const SocketGeometry(),
      transform: Matrix4.translation(localOffset),
      parent: parent,
    );

void _expectMatrixClose(Matrix4 a, Matrix4 b, {String? reason}) {
  for (var e = 0; e < 16; e++) {
    expect(a.storage[e], closeTo(b.storage[e], 1e-6), reason: '$reason, e=$e');
  }
}

void main() {
  group('poseOf', () {
    test('a joint parented under another joint of the same skeleton composes '
        'through it, the way the real scene would', () {
      final project = ModelProject(
        objects: <ModelObject>[
          _joint(1, localOffset: Vector3.zero()),
          _joint(2, parent: 1, localOffset: Vector3(0, 0.5, 0)),
        ],
      );
      final skeleton = ProjectSkeleton(
        joints: <int>[1, 2],
        inverseBindMatrices: <Matrix4>[Matrix4.identity(), Matrix4.identity()],
      );

      final Pose pose = poseOf(project, skeleton);
      final world = pose.worldMatrices();

      expect(pose.parents, <int>[-1, 0]);
      _expectMatrixClose(
        world[0],
        Matrix4.identity(),
        reason: 'the root joint has no ancestor at all',
      );
      _expectMatrixClose(
        world[1],
        Matrix4.translation(Vector3(0, 0.5, 0)),
        reason: 'the tip composes onto its own parent joint',
      );
    });

    test('a root joint hung under something outside the skeleton still answers '
        'for what that ancestor contributes', () {
      // `1` is a rig controller, not itself a joint of `skeleton` below —
      // exactly the shape `anim-21`'s own auto-rig gives a skeleton root
      // parented under a controller object.
      final project = ModelProject(
        objects: <ModelObject>[
          ModelObject(
            id: 1,
            name: 'controller',
            geometry: const SocketGeometry(),
            transform: Matrix4.translation(Vector3(2, 0, 0)),
          ),
          _joint(2, parent: 1, localOffset: Vector3(0, 1, 0)),
        ],
      );
      final skeleton = ProjectSkeleton(
        joints: <int>[2],
        inverseBindMatrices: <Matrix4>[Matrix4.identity()],
      );

      final world = poseOf(project, skeleton).worldMatrices();

      // Mutation: read the joint's own bare `ModelObject.transform`
      // instead of `worldTransformOf` when it has no in-skeleton parent —
      // that answers `(0, 1, 0)` and silently drops the controller's own
      // `(2, 0, 0)`, which is not where this joint actually sits in the
      // real scene `scene_sync.dart` builds.
      _expectMatrixClose(
        world.single,
        worldTransformOf(project, 2),
        reason: 'the controller above the root joint has to count',
      );
      _expectMatrixClose(world.single, Matrix4.translation(Vector3(2, 1, 0)));
    });

    test('a joint id the project does not hold reads as identity', () {
      final skeleton = ProjectSkeleton(
        joints: <int>[99],
        inverseBindMatrices: <Matrix4>[Matrix4.identity()],
      );

      final world = poseOf(const ModelProject(), skeleton).worldMatrices();

      _expectMatrixClose(world.single, Matrix4.identity());
    });
  });
}
