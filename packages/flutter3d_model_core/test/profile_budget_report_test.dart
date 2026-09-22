/// `anim-24`'s own acceptance: `maxJoints=16` on 19 joints reads as an
/// orange bar. [ProfileBudgetReport.of] is the number a bar reads before any
/// bar exists — `Screen 19` itself is `ui-28`'s undone Flutter shell.
///
///     dart test test/profile_budget_report_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A skeleton of [jointCount] joints and one skinned cube bound to the
/// first, each vertex given [influences] weighted joints (clamped to
/// [jointCount] and to 4, `VertexAttributes`' own slot count) — the same
/// shape `rig_issues_test.dart`'s own `_cleanRig` builds, extended with a
/// controllable influence count for this row's own bar.
ModelProject _rig({required int jointCount, int influences = 1}) {
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

  final used = influences
      .clamp(1, 4)
      .clamp(0, jointCount == 0 ? 1 : jointCount);
  final weight = 1.0 / used;
  final joints = List<double>.generate(4, (i) => i < used ? i.toDouble() : 0);
  final weights = List<double>.generate(4, (i) => i < used ? weight : 0);
  final mesh = EditMesh.cuboid();
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    mesh
      ..beginStep()
      ..setSkin(
        v,
        VertexAttributes(
          joints: Vector4(joints[0], joints[1], joints[2], joints[3]),
          weights: Vector4(weights[0], weights[1], weights[2], weights[3]),
        ),
      )
      ..endStep();
  }
  return project.added(
    (id) => ModelObject(
      id: id,
      name: 'body',
      geometry: EditedGeometry(mesh),
      transform: Matrix4.identity(),
      skeletonIndex: 0,
    ),
  );
}

void main() {
  test('an empty project spends nothing against every budget', () {
    final report = ProfileBudgetReport.of(const ModelProject());
    expect(report.triangles.used, 0);
    expect(report.joints.used, 0);
    expect(report.influences.used, 0);
    expect(report.textureBytes.used, 0);
    expect(report.anyOver, isFalse);
  });

  test('a cube reads 12 triangles under the default 500000 budget', () {
    final report = ProfileBudgetReport.of(_rig(jointCount: 1));
    expect(report.triangles.used, 12);
    expect(report.triangles.over, isFalse);
  });

  test('19 joints on a 16-joint cap is an over bar, not a thrown error', () {
    final project = _rig(jointCount: 19);
    final report = ProfileBudgetReport.of(
      project.copyWith(profile: const ProjectProfile(maxJoints: 16)),
    );
    expect(report.joints.used, 19);
    expect(report.joints.limit, 16);
    expect(report.joints.over, isTrue);
    expect(report.anyOver, isTrue);
  });

  test('the widest influence count used is read, not the profile limit', () {
    final project = _rig(jointCount: 4, influences: 3);
    final report = ProfileBudgetReport.of(project);
    expect(report.influences.used, 3);
  });

  test('more influences used than the profile allows is an over bar', () {
    final project = _rig(jointCount: 4, influences: 4);
    final report = ProfileBudgetReport.of(
      project.copyWith(profile: const ProjectProfile(maxInfluences: 2)),
    );
    expect(report.influences.used, 4);
    expect(report.influences.over, isTrue);
  });

  test('wireframe is always reported declined, honestly', () {
    expect(
      ProfileBudgetReport.of(const ModelProject()).wireframeDeclined,
      isTrue,
    );
  });

  test('BudgetUsage.fraction never divides by a zero limit', () {
    expect(const BudgetUsage(used: 0, limit: 0).fraction, 0.0);
    expect(const BudgetUsage(used: 5, limit: 0).fraction, 1.0);
    expect(const BudgetUsage(used: 5, limit: 10).fraction, 0.5);
  });
}
