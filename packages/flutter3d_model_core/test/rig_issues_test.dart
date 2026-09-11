/// `anim-13`'s own row: `rigIssues(project, profile)`, one test per named
/// problem — "по проверке с мутацией" read literally: each test mutates a
/// clean rig into exactly the shape one check exists for, and nothing else.
///
///     dart test test/rig_issues_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A joint object, a skinned cube object bound to it, and the skeleton that
/// ties them together — one joint, every vertex bound to it at full weight,
/// nothing this row's checks should flag.
ModelProject _cleanRig({int jointCount = 1}) {
  var project = const ModelProject();
  final jointIds = <int>[];
  for (var i = 0; i < jointCount; i++) {
    project = project.added(
      (id) => ModelObject(
        id: id,
        name: 'joint$i',
        geometry: const SocketGeometry(),
        transform: Matrix4.identity(),
      ),
    );
    jointIds.add(project.objects.last.id);
  }
  project = project.copyWith(
    skeletons: <ProjectSkeleton>[
      ProjectSkeleton(
        joints: jointIds,
        inverseBindMatrices: <Matrix4>[
          for (var i = 0; i < jointCount; i++) Matrix4.identity(),
        ],
      ),
    ],
  );

  final mesh = EditMesh.cuboid();
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    mesh
      ..beginStep()
      ..setSkin(
        v,
        VertexAttributes(
          joints: Vector4(0, 0, 0, 0),
          weights: Vector4(1, 0, 0, 0),
        ),
      )
      ..endStep();
  }
  project = project.added(
    (id) => ModelObject(
      id: id,
      name: 'body',
      geometry: EditedGeometry(mesh),
      transform: Matrix4.identity(),
      skeletonIndex: 0,
    ),
  );
  return project;
}

void main() {
  test('a clean rig has no issues', () {
    expect(rigIssues(_cleanRig(), const ProjectProfile()), isEmpty);
  });

  test('more joints than the hard 64-joint shader cap is an error', () {
    final project = _cleanRig(jointCount: 65);
    final issues = rigIssues(project, const ProjectProfile());
    expect(
      issues,
      contains(
        predicate<ExportIssue>(
          (i) => i.severity == ExportSeverity.error && i.message.contains('64'),
        ),
      ),
    );
  });

  test('more joints than the profile budget, under the hard cap, is a warning', () {
    final project = _cleanRig(jointCount: 3);
    final issues = rigIssues(project, const ProjectProfile(maxJoints: 2));
    expect(
      issues,
      contains(
        predicate<ExportIssue>(
          (i) =>
              i.severity == ExportSeverity.warning &&
              i.message.contains('joints') &&
              i.message.contains('2'),
        ),
      ),
    );
  });

  test('a joint with a non-uniform scale is a warning naming that object', () {
    var project = _cleanRig();
    final joint = project.objects.firstWhere((o) => o.name == 'joint0');
    project = project.withObject(
      joint.copyWith(
        transform: Matrix4.identity()..scaleByVector3(Vector3(2.0, 1.0, 1.0)),
      ),
    );
    final issues = rigIssues(project, const ProjectProfile());
    expect(
      issues,
      contains(
        predicate<ExportIssue>(
          (i) =>
              i.severity == ExportSeverity.warning &&
              i.message.contains('non-uniform scale') &&
              i.object?.id == joint.id,
        ),
      ),
    );
  });

  test('a vertex with no weight at all is a warning', () {
    final project = _cleanRig();
    final body = project.objects.firstWhere((o) => o.name == 'body');
    final mesh = (body.geometry as EditedGeometry).mesh;
    mesh
      ..beginStep()
      ..setSkin(0, VertexAttributes(joints: Vector4.zero(), weights: Vector4.zero()))
      ..endStep();
    final issues = rigIssues(project, const ProjectProfile());
    expect(
      issues,
      contains(
        predicate<ExportIssue>(
          (i) => i.severity == ExportSeverity.warning && i.message.contains('no weight'),
        ),
      ),
    );
  });

  test('a vertex whose weights do not sum to one is a warning', () {
    final project = _cleanRig();
    final body = project.objects.firstWhere((o) => o.name == 'body');
    final mesh = (body.geometry as EditedGeometry).mesh;
    mesh
      ..beginStep()
      ..setSkin(
        0,
        VertexAttributes(joints: Vector4(0, 0, 0, 0), weights: Vector4(0.5, 0.2, 0, 0)),
      )
      ..endStep();
    final issues = rigIssues(project, const ProjectProfile());
    expect(
      issues,
      contains(
        predicate<ExportIssue>(
          (i) =>
              i.severity == ExportSeverity.warning &&
              i.message.contains('do not sum to one'),
        ),
      ),
    );
  });

  test('a vertex over the profile\'s influence budget is a warning', () {
    final project = _cleanRig(jointCount: 3);
    final body = project.objects.firstWhere((o) => o.name == 'body');
    final mesh = (body.geometry as EditedGeometry).mesh;
    mesh
      ..beginStep()
      ..setSkin(
        0,
        VertexAttributes(
          joints: Vector4(0, 1, 2, 0),
          weights: Vector4(0.4, 0.3, 0.3, 0),
        ),
      )
      ..endStep();
    final issues = rigIssues(project, const ProjectProfile(maxInfluences: 2));
    expect(
      issues,
      contains(
        predicate<ExportIssue>(
          (i) => i.severity == ExportSeverity.warning && i.message.contains('influences'),
        ),
      ),
    );
  });

  test('a weight naming a joint index outside the skin is an error', () {
    final project = _cleanRig();
    final body = project.objects.firstWhere((o) => o.name == 'body');
    final mesh = (body.geometry as EditedGeometry).mesh;
    mesh
      ..beginStep()
      ..setSkin(
        0,
        VertexAttributes(joints: Vector4(7, 0, 0, 0), weights: Vector4(1, 0, 0, 0)),
      )
      ..endStep();
    final issues = rigIssues(project, const ProjectProfile());
    expect(
      issues,
      contains(
        predicate<ExportIssue>(
          (i) =>
              i.severity == ExportSeverity.error &&
              i.message.contains('outside') &&
              i.message.contains('joint index'),
        ),
      ),
    );
  });

  test('a joint no vertex is weighted to is a warning', () {
    final project = _cleanRig(jointCount: 2);
    final issues = rigIssues(project, const ProjectProfile());
    expect(
      issues,
      contains(
        predicate<ExportIssue>(
          (i) =>
              i.severity == ExportSeverity.warning &&
              i.message.contains('no vertex is weighted to'),
        ),
      ),
    );
  });

  test('a track naming an object the project does not have is an error', () {
    final project = _cleanRig().copyWith(
      clips: <ProjectClip>[
        ProjectClip(
          name: 'idle',
          tracks: <ProjectTrack>[
            ProjectTrack(
              objectId: 999999,
              track: AnimationTrack(
                nodeIndex: 0,
                path: AnimationPath.translation,
                interpolation: AnimationInterpolation.linear,
                times: Float32List.fromList(<double>[0.0]),
                values: Float32List.fromList(<double>[0.0, 0.0, 0.0]),
                componentCount: 3,
              ),
            ),
          ],
        ),
      ],
    );
    final issues = rigIssues(project, const ProjectProfile());
    expect(
      issues,
      contains(
        predicate<ExportIssue>(
          (i) =>
              i.severity == ExportSeverity.error &&
              i.message.contains('999999') &&
              i.message.contains('does not have'),
        ),
      ),
    );
  });
}
