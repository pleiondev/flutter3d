/// `S2`'s own pure helpers: `TimelinePanel.onSetKey`'s tap resolved into a
/// real `PoseJoint`, the animation mode's own status-line sentence, and the
/// skeleton lookup both draw on.
///
///     flutter test test/animation_wiring_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;
import 'package:flutter3d_modeler/src/animation_wiring.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

ProjectClip _clip() => ProjectClip(
  name: 'walk',
  tracks: <ProjectTrack>[
    ProjectTrack(
      objectId: 7,
      track: AnimationTrack(
        nodeIndex: 0,
        path: AnimationPath.rotation,
        interpolation: AnimationInterpolation.linear,
        times: Float32List.fromList(<double>[0.0]),
        values: Float32List.fromList(<double>[0, 0, 0, 1]),
        componentCount: 4,
      ),
    ),
  ],
);

void main() {
  group('poseJointForSetKey', () {
    test('reads the joint and path off the tapped track, snapping the '
        'frame at the given fps', () {
      final command = poseJointForSetKey(
        clip: _clip(),
        clipIndex: 2,
        trackIndex: 0,
        time: 0.5,
        fps: 30.0,
      );

      expect(command, isNotNull);
      expect(command!.joint, 7);
      expect(command.path, AnimationPath.rotation);
      expect(command.clipIndex, 2);
      // Mutation: truncate instead of round, or ignore fps entirely.
      // KeyTable.frameOfTime(0.5, 30) = round(15.0) = 15.
      expect(command.frame, 15);
    });

    test('snaps to the nearest frame, not the one before it', () {
      // 0.501 * 30 = 15.03, which rounds to 15 — a hair past a frame
      // boundary still reads as the frame it was meant for.
      final command = poseJointForSetKey(
        clip: _clip(),
        clipIndex: 0,
        trackIndex: 0,
        time: 0.501,
        fps: 30.0,
      );

      expect(command!.frame, 15);
    });

    test('an out-of-range track index is refused, not thrown', () {
      final command = poseJointForSetKey(
        clip: _clip(),
        clipIndex: 0,
        trackIndex: 3,
        time: 0.5,
        fps: 30.0,
      );

      expect(command, isNull);
    });

    test('a negative track index is refused too', () {
      final command = poseJointForSetKey(
        clip: _clip(),
        clipIndex: 0,
        trackIndex: -1,
        time: 0.5,
        fps: 30.0,
      );

      expect(command, isNull);
    });
  });

  group('animationModeSummary', () {
    test('reads "Bones N · actions N · influences M per vertex"', () {
      expect(
        animationModeSummary(bones: 24, actions: 3, maxInfluences: 4),
        'Bones 24 · actions 3 · influences 4 per vertex',
      );
    });

    test('a profile with a different influence cap is not hard-coded to 4', () {
      expect(
        animationModeSummary(bones: 0, actions: 0, maxInfluences: 8),
        contains('influences 8 per vertex'),
      );
    });
  });

  group('heldSkeletonOf', () {
    test('null with nothing held', () {
      expect(heldSkeletonOf(const ModelProject(), null), isNull);
    });

    test('null when the held object has no skeleton of its own', () {
      final object = ModelObject(
        id: 1,
        name: 'cube',
        geometry: const SocketGeometry(),
        transform: vm.Matrix4.identity(),
      );

      expect(heldSkeletonOf(const ModelProject(), object), isNull);
    });

    test('the skeleton at the held object\'s own index', () {
      final skeleton = ProjectSkeleton(
        joints: const <int>[1],
        inverseBindMatrices: <vm.Matrix4>[vm.Matrix4.identity()],
      );
      final project = const ModelProject().copyWith(
        skeletons: <ProjectSkeleton>[skeleton],
      );
      final object = ModelObject(
        id: 1,
        name: 'root',
        geometry: const SocketGeometry(),
        transform: vm.Matrix4.identity(),
        skeletonIndex: 0,
      );

      expect(heldSkeletonOf(project, object), same(skeleton));
    });
  });
}
