/// `anim-18`'s own golden: `modeler-retarget.png`, a CPU-rendered frame of
/// the target rig after `retargetClip` runs a one-key clip from a smaller
/// source rig onto it — built the same way `frame_test.dart`'s own
/// "skeleton overlay" test builds a two-joint skinned rig through
/// `ModelerStage.fromProject`/`SceneSync`, per `view-27d`'s own "built from
/// a project, not a hand-assembled `Skeleton`" rule.
///
///     flutter test test/retarget_frame_test.dart
///     flutter test test/retarget_frame_test.dart --update-goldens
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_rig/flutter3d_rig.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A two-joint rig — `root`/`tip`, the same names on both sides so
/// `autoMap` matches them exactly — with a skinned cube over it when
/// [skinned], scaled by [scale] along the joint's own reach.
({ModelProject project, ProjectSkeleton skeleton}) _twoJointRig({
  required double scale,
  bool skinned = false,
}) {
  final objects = <ModelObject>[
    ModelObject(
      id: 1,
      name: 'root',
      geometry: const SocketGeometry(),
      transform: Matrix4.identity(),
    ),
    ModelObject(
      id: 2,
      name: 'tip',
      geometry: const SocketGeometry(),
      transform: Matrix4.translation(Vector3(0, scale, 0)),
      parent: 1,
    ),
  ];
  if (!skinned) {
    return (
      project: ModelProject(objects: objects, nextId: 3),
      skeleton: ProjectSkeleton(
        joints: <int>[1, 2],
        inverseBindMatrices: <Matrix4>[Matrix4.identity(), Matrix4.identity()],
      ),
    );
  }

  final mesh = EditMesh.cuboid();
  mesh.beginStep();
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    if (!mesh.isVertexAlive(v)) continue;
    if (mesh.positionOf(v).y > 0) {
      mesh.setSkin(
        v,
        VertexAttributes(
          joints: Vector4(1, 0, 0, 0),
          weights: Vector4(1, 0, 0, 0),
        ),
      );
    }
  }
  mesh.endStep();

  var project = ModelProject(
    objects: <ModelObject>[
      ...objects,
      ModelObject(
        id: 3,
        name: 'cube',
        geometry: EditedGeometry(mesh),
        transform: Matrix4.identity(),
        skeletonIndex: 0,
      ),
    ],
    nextId: 4,
  );
  final bindPose = poseOf(
    project,
    ProjectSkeleton(
      joints: <int>[1, 2],
      inverseBindMatrices: <Matrix4>[Matrix4.identity(), Matrix4.identity()],
    ),
  );
  final skeleton = ProjectSkeleton(
    joints: <int>[1, 2],
    inverseBindMatrices: <Matrix4>[
      for (final world in bindPose.worldMatrices())
        Matrix4.copy(world)..invert(),
    ],
  );
  project = project.copyWith(skeletons: <ProjectSkeleton>[skeleton]);
  return (project: project, skeleton: skeleton);
}

void main() {
  test('the target rig, posed by a one-key retargeted clip, matches its '
      'reference', () async {
    final source = _twoJointRig(scale: 0.5);
    final target = _twoJointRig(scale: 1.0, skinned: true);

    final bend = Quaternion.axisAngle(Vector3(1, 0, 0), 0.6)..normalize();
    final sourceClip = ProjectClip(
      name: 'bend',
      tracks: <ProjectTrack>[
        ProjectTrack(
          objectId: 2,
          track: AnimationTrack(
            nodeIndex: 0,
            path: AnimationPath.rotation,
            interpolation: AnimationInterpolation.linear,
            times: Float32List.fromList(<double>[0.0]),
            values: Float32List.fromList(<double>[
              bend.x,
              bend.y,
              bend.z,
              bend.w,
            ]),
            componentCount: 4,
          ),
        ),
      ],
    );

    final boneMap = autoMap(<String>['root', 'tip'], <String>['root', 'tip']);
    expect(boneMap.length, 2);

    final retargeted = retargetClip(
      sourceClip: sourceClip,
      sourceProject: source.project,
      sourceSkeleton: source.skeleton,
      targetProject: target.project,
      targetSkeleton: target.skeleton,
      boneMap: boneMap,
      // No leg chain on this rig for `lockFeet`'s own two-bone IK to find —
      // it simply finds no `leftHip`/`leftKnee`/`leftAnkle` and does
      // nothing, but turning it off keeps this test about `retargetClip`'s
      // own rotation math alone.
      lockFeet: false,
    );

    // A one-key clip, `anim-18`'s own row: the single retargeted rotation,
    // applied straight onto the target's own `tip` object — the same
    // "an ordinary edit through the door a `PoseJoint` also uses" pattern
    // `frame_test.dart`'s own skeleton-overlay test already poses a joint
    // with.
    final tipTrack = retargeted.tracks.firstWhere((t) => t.objectId == 2);
    expect(tipTrack.track.times, hasLength(1));
    final v = tipTrack.track.values;
    final posedProject = target.project.withObject(
      target.project[2]!.copyWith(
        transform: Matrix4.compose(
          Vector3(0, 1.0, 0),
          Quaternion(v[0], v[1], v[2], v[3]),
          Vector3(1, 1, 1),
        ),
      ),
    );

    final frame = await renderFrame(
      width: 240,
      height: 160,
      build: (FrameRequest request) {
        final stage = ModelerStage.fromProject(
          device: request.device,
          project: posedProject,
        );
        stage.frameSubject();
        return (scene: stage.scene, camera: stage.camera);
      },
    );

    await expectMatchesGolden(frame, 'test/goldens/modeler-retarget.png');
  });
}
