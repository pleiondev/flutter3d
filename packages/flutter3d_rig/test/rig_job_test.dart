/// `anim-25`'s own `RetargetClipJobRequest` and `BindWeightsJobRequest` —
/// the two `RigJob` kinds that live in this package rather than in
/// `flutter3d_model_core`. See this package's own `lib/src/rig_job.dart`
/// for why.
///
///     dart test test/rig_job_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_rig/flutter3d_rig.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('retargetClipJobRequestFor / RetargetClipJobRequest.run', () {
    ({ModelProject project, ProjectSkeleton skeleton}) twoJointRig() {
      final objects = <ModelObject>[
        ModelObject(
          id: 1,
          name: 'root',
          geometry: const SocketGeometry(),
          transform: Matrix4.identity(),
        ),
        ModelObject(
          id: 2,
          name: 'child',
          geometry: const SocketGeometry(),
          transform: Matrix4.translation(Vector3(0, 1, 0)),
          parent: 1,
        ),
      ];
      final skeleton = ProjectSkeleton(
        joints: <int>[1, 2],
        inverseBindMatrices: <Matrix4>[Matrix4.identity(), Matrix4.identity()],
      );
      return (
        project: ModelProject(
          objects: objects,
          skeletons: <ProjectSkeleton>[skeleton],
        ),
        skeleton: skeleton,
      );
    }

    ProjectClip poseClip(int childId) => ProjectClip(
      name: 'pose',
      tracks: <ProjectTrack>[
        ProjectTrack(
          objectId: childId,
          track: AnimationTrack(
            nodeIndex: 0,
            path: AnimationPath.rotation,
            interpolation: AnimationInterpolation.linear,
            times: Float32List.fromList(<double>[0, 1]),
            values: Float32List.fromList(<double>[
              0,
              0,
              0,
              1,
              ...(() {
                final q = Quaternion.axisAngle(Vector3(1, 0, 0), 0.4)
                  ..normalize();
                return <double>[q.x, q.y, q.z, q.w];
              })(),
            ]),
            componentCount: 4,
          ),
        ),
      ],
    );

    test('retargeting a skeleton onto itself matches retargetClip directly, '
        'byte for byte', () async {
      final rig = twoJointRig();
      final clip = poseClip(2);
      final project = rig.project.copyWith(clips: <ProjectClip>[clip]);
      final boneMap = BoneMap(<String, String>{
        'root': 'root',
        'child': 'child',
      });

      final request = retargetClipJobRequestFor(
        sourceProject: project,
        sourceSkeletonIndex: 0,
        sourceClipIndex: 0,
        targetProject: project,
        targetSkeletonIndex: 0,
        boneMap: boneMap,
        lockFeet: false,
      )!;

      final direct = retargetClip(
        sourceClip: clip,
        sourceProject: project,
        sourceSkeleton: rig.skeleton,
        targetProject: project,
        targetSkeleton: rig.skeleton,
        boneMap: boneMap,
        lockFeet: false,
      );
      final throughJob = await request.run();

      expect(throughJob.tracks, hasLength(direct.tracks.length));
      for (var i = 0; i < throughJob.tracks.length; i++) {
        expect(throughJob.tracks[i].objectId, direct.tracks[i].objectId);
        expect(throughJob.tracks[i].track.times, direct.tracks[i].track.times);
        expect(
          throughJob.tracks[i].track.values,
          direct.tracks[i].track.values,
        );
      }
    });

    test('null for a source skeleton/clip or target skeleton index that is '
        'not there', () {
      final rig = twoJointRig();
      final project = rig.project.copyWith(clips: <ProjectClip>[poseClip(2)]);
      final boneMap = BoneMap(<String, String>{
        'root': 'root',
        'child': 'child',
      });

      expect(
        retargetClipJobRequestFor(
          sourceProject: project,
          sourceSkeletonIndex: 9,
          sourceClipIndex: 0,
          targetProject: project,
          targetSkeletonIndex: 0,
          boneMap: boneMap,
        ),
        isNull,
      );
      expect(
        retargetClipJobRequestFor(
          sourceProject: project,
          sourceSkeletonIndex: 0,
          sourceClipIndex: 9,
          targetProject: project,
          targetSkeletonIndex: 0,
          boneMap: boneMap,
        ),
        isNull,
      );
      expect(
        retargetClipJobRequestFor(
          sourceProject: project,
          sourceSkeletonIndex: 0,
          sourceClipIndex: 0,
          targetProject: project,
          targetSkeletonIndex: 9,
          boneMap: boneMap,
        ),
        isNull,
      );
    });

    test(
      'applying the result through ApplyClipResult appends the clip',
      () async {
        final rig = twoJointRig();
        final clip = poseClip(2);
        final project = rig.project.copyWith(clips: <ProjectClip>[clip]);
        final boneMap = BoneMap(<String, String>{
          'root': 'root',
          'child': 'child',
        });
        final request = retargetClipJobRequestFor(
          sourceProject: project,
          sourceSkeletonIndex: 0,
          sourceClipIndex: 0,
          targetProject: project,
          targetSkeletonIndex: 0,
          boneMap: boneMap,
          lockFeet: false,
        )!;
        final history = ModelHistory(project);

        final result = await request.run();
        expect(history.run(ApplyClipResult(clip: result)), isNull);

        expect(history.project.clips, hasLength(2));
      },
    );
  });

  group('bindWeightsJobRequestFor / BindWeightsJobRequest.run', () {
    // A unit cuboid, bottom vertices at y = -0.5 and top vertices at
    // y = 0.5 (`EditMesh.cuboid`'s own layout) — two bones, one hugging
    // each half, so every vertex has an unambiguous closest bone and the
    // test needs no tie-breaking.
    List<BoneSegment> twoBones() => <BoneSegment>[
      BoneSegment(Vector3(0, -1, 0), Vector3(0, -0.5, 0), name: 'lower'),
      BoneSegment(Vector3(0, 0.5, 0), Vector3(0, 1, 0), name: 'upper'),
    ];

    ModelProject cubeProject() => const ModelProject().added(
      (int id) => ModelObject(
        id: id,
        name: 'cube',
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.identity(),
      ),
    );

    test('captures the object\'s own version, mesh and bones', () {
      final project = cubeProject();
      final request = bindWeightsJobRequestFor(
        project: project,
        objectId: 1,
        bones: twoBones(),
      );

      expect(request, isNotNull);
      expect(request!.objectId, 1);
      expect(request.baseVersion, project[1]!.version);
      expect(request.bones, hasLength(2));
    });

    test('null when objectId names no object', () {
      expect(
        bindWeightsJobRequestFor(
          project: cubeProject(),
          objectId: 99,
          bones: twoBones(),
        ),
        isNull,
      );
    });

    test('every live vertex ends up bound, weights summing to 1', () async {
      final project = cubeProject();
      final request = bindWeightsJobRequestFor(
        project: project,
        objectId: 1,
        bones: twoBones(),
      )!;

      final result = await request.run();
      final bound = EditMesh.fromBytes(result.meshBytes);

      for (var v = 0; v < bound.vertexSlotCount; v++) {
        if (!bound.isVertexAlive(v)) continue;
        final pairs = weightsOf(bound, v);
        expect(pairs, isNotEmpty);
        final total = pairs.fold<double>(0, (sum, p) => sum + p.weight);
        expect(total, closeTo(1.0, 1e-6));
      }

      // The bottom four vertices (0, 1, 4, 5 — `EditMesh.cuboid`'s own
      // layout) sit against the lower bone (joint 0) and nowhere near the
      // upper one; the top four the other way round.
      for (final v in <int>[0, 1, 4, 5]) {
        final pairs = weightsOf(bound, v);
        expect(pairs.single.joint, 0);
      }
      for (final v in <int>[2, 3, 6, 7]) {
        final pairs = weightsOf(bound, v);
        expect(pairs.single.joint, 1);
      }
    });

    test(
      'through the job matches applying bindWeights directly, byte for byte',
      () async {
        final project = cubeProject();
        final bones = twoBones();
        final request = bindWeightsJobRequestFor(
          project: project,
          objectId: 1,
          bones: bones,
        )!;

        final viaJob = await request.run();

        final direct = EditMesh.cuboid();
        final positions = <Vector3>[
          for (var v = 0; v < direct.vertexSlotCount; v++)
            direct.isVertexAlive(v) ? direct.positionOf(v) : Vector3.zero(),
        ];
        final triangles = <int>[];
        for (var face = 0; face < direct.faceSlotCount; face++) {
          if (!direct.isFaceAlive(face)) continue;
          final loop = direct.verticesOf(face);
          for (var i = 1; i < loop.length - 1; i++) {
            triangles..add(loop[0])..add(loop[i])..add(loop[i + 1]);
          }
        }
        final normalized = normalizeSkinWeights(
          pruneSkinWeights(
            bindWeights(positions: positions, triangles: triangles, bones: bones),
          ),
        );
        direct.beginStep();
        for (final entry in normalized.entries) {
          if (!direct.isVertexAlive(entry.key)) continue;
          direct.setSkin(entry.key, toVertexAttributes(entry.value));
        }
        direct.endStep();

        expect(viaJob.meshBytes, equals(direct.toBytes()));
      },
    );

    test('a stale baseVersion is refused by ApplyJobResult', () async {
      final project = cubeProject();
      final request = bindWeightsJobRequestFor(
        project: project,
        objectId: 1,
        bones: twoBones(),
      )!;
      final history = ModelHistory(project);
      // Something else touches the object before the job comes back.
      expect(history.run(Rename(id: 1, to: 'renamed')), isNull);

      final result = await request.run();
      final refusal = history.run(ApplyJobResult.of(result));

      expect(refusal, isNotNull);
    });
  });
}
