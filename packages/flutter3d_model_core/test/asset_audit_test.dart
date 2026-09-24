/// `AssetAudit` against `test/fixtures/broken_asset.glb`, one fault per
/// check — see `broken_asset.dart` for what the file is and why each number
/// below is the one it should be.
///
///     dart test test/asset_audit_test.dart
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Future<ModelProject> _broken() async => fromModelDocument(
  await GltfLoader().load(
    File('test/fixtures/broken_asset.glb').readAsBytesSync(),
  ),
);

List<AuditFinding> _of(AssetAudit audit, AuditCheck check) => <AuditFinding>[
  for (final AuditFinding finding in audit.findings)
    if (finding.check == check) finding,
];

void main() {
  group('the broken fixture', () {
    late ModelProject project;
    late AssetAudit audit;
    setUpAll(() async {
      project = await _broken();
      audit = AssetAudit.of(project);
    });

    test('measures 190 across and reads as centimetres', () {
      expect(audit.size, closeTo(190, 1e-4));
      // Mutation: widen `assetMaxSize` to 1000 — no units finding at all.
      final units = _of(audit, AuditCheck.units);
      expect(units, hasLength(1));
      expect(units.single.message, contains('1.90 m'));
      expect(units.single.message, contains('unit "cm"'));
    });

    test('has its origin a base centre away from where it stands', () {
      expect(audit.baseCentre!.x, closeTo(100, 1e-4));
      expect(audit.baseCentre!.y, closeTo(20, 1e-4));
      expect(audit.baseCentre!.z, closeTo(0, 1e-4));
      expect(
        audit.pivotDistance,
        closeTo(math.sqrt(100 * 100 + 20 * 20), 1e-3),
      );
      expect(_of(audit, AuditCheck.pivot), hasLength(1));
    });

    test('carries one material under two names', () {
      // Mutation: pass `named: true` to `materialKey` in the audit — the
      // names differ, so the group disappears.
      expect(audit.duplicateMaterials, <List<int>>[
        <int>[0, 1],
      ]);
      final materials = _of(audit, AuditCheck.materials);
      expect(materials, hasLength(1));
      expect(materials.single.message, contains('"Material.001"'));
    });

    test('counts the welded degenerate and the glued fin on the crate', () {
      final crate = audit.meshes.singleWhere(
        (MeshAudit m) => m.object.name == 'crate',
      );
      expect(crate.degenerate, 1);
      expect(crate.nonManifold, 1);
      expect(crate.flipped, 0);
      final lid = audit.meshes.singleWhere(
        (MeshAudit m) => m.object.name == 'lid',
      );
      expect((lid.degenerate, lid.nonManifold, lid.flipped), (0, 0, 0));
      // One finding for the crate, none for the lid.
      final mesh = _of(audit, AuditCheck.mesh);
      expect(mesh, hasLength(1));
      expect(mesh.single.message, contains('"crate"'));
      expect(mesh.single.message, contains('1 triangle with no area'));
      expect(mesh.single.message, contains('1 edge shared'));
    });

    test('carries the triangle budget from the project\'s own profile', () {
      expect(_of(audit, AuditCheck.readiness), isEmpty);
      final tight = project.copyWith(
        profile: const ProjectProfile(maxTriangles: 10),
      );
      final readiness = _of(AssetAudit.of(tight), AuditCheck.readiness);
      expect(readiness, hasLength(1));
      expect(readiness.single.message, contains('allows 10'));
    });

    test('says what it measured and lists every finding', () {
      final lines = audit.says.split('\n');
      expect(lines.first, contains('100.00 m × 190.00 m × 100.00 m'));
      expect(lines[1], '${audit.findings.length} findings:');
      expect(lines.skip(2), hasLength(audit.findings.length));
      expect(audit.clean, isFalse);
    });
  });

  test('a metre cube standing on the origin is clean', () {
    // A profile that holds quads, so the cuboid's own six faces are not a
    // readiness warning — the audit carries those whole, and this test is
    // about the measurements.
    final project =
        const ModelProject(
          profile: ProjectProfile(requireTriangles: false),
        ).added(
          (int id) => ModelObject(
            id: id,
            name: 'cube',
            geometry: EditedGeometry(EditMesh.cuboid(size: Vector3.all(1))),
            transform: Matrix4.translationValues(0, 0.5, 0),
          ),
        );
    final audit = AssetAudit.of(project);
    expect(audit.size, closeTo(1, 1e-6));
    expect(audit.pivotDistance, closeTo(0, 1e-6));
    expect(audit.clean, isTrue, reason: audit.says);
    expect(audit.says, endsWith('nothing to fix'));
  });

  test('a millimetre model is flagged small, a parametric one measured', () {
    final project = const ModelProject().added(
      (int id) => ModelObject(
        id: id,
        name: 'grain',
        geometry: ParametricGeometry(
          ParametricCuboid(size: Vector3.all(0.002)),
        ),
        transform: Matrix4.translationValues(0, 0.001, 0),
      ),
    );
    final audit = AssetAudit.of(project);
    expect(audit.size, closeTo(0.002, 1e-6));
    final units = _of(audit, AuditCheck.units);
    expect(units, hasLength(1));
    expect(units.single.message, contains('0.0020 m'));
    expect(_of(audit, AuditCheck.pivot), isEmpty);
  });

  test('an empty project has nothing to measure and nothing to fix', () {
    final audit = AssetAudit.of(const ModelProject());
    expect(audit.bounds, isNull);
    expect(audit.clean, isTrue);
    expect(audit.says, 'nothing drawn to measure\nnothing to fix');
  });
}
