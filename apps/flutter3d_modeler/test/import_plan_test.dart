/// `ImportPlan`: `ui-16`'s own `import_plan_test` without Flutter — what an
/// import screen decides before and after a file decodes.
///
///     dart test test/import_plan_test.dart
library;

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/import_plan.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelDocument _documentWithCuboid(
  Vector3 size, {
  List<String> warnings = const <String>[],
}) {
  final mesh = CuboidShape(size: size).build();
  return PlainModelDocument(
    surfaces: <ModelSurface>[ModelSurface(mesh: mesh)],
    warnings: warnings,
  );
}

void main() {
  group('refuseBeforeDecoding', () {
    test('a file under the web limit is not refused', () {
      expect(refuseBeforeDecoding(fileSizeBytes: 1024, onWeb: true), isNull);
    });

    test('a file over the web limit is refused, naming both sizes', () {
      final said = refuseBeforeDecoding(
        fileSizeBytes: 40 * 1024 * 1024,
        onWeb: true,
        webFileSizeLimitBytes: 30 * 1024 * 1024,
      );
      expect(said, isNotNull);
      expect(said, contains('40.0 MB'));
      expect(said, contains('30 MB'));
    });

    test('the same oversized file is not refused off the web', () {
      expect(
        refuseBeforeDecoding(
          fileSizeBytes: 40 * 1024 * 1024,
          onWeb: false,
          webFileSizeLimitBytes: 30 * 1024 * 1024,
        ),
        isNull,
      );
    });
  });

  test('ImportPlan.triangleCount reads the document\'s own count, not a '
      'copy of it', () {
    final document = PlainModelDocument(
      surfaces: <ModelSurface>[
        ModelSurface(mesh: CuboidShape(size: Vector3(1, 1, 1)).build()),
        ModelSurface(mesh: CuboidShape(size: Vector3(1, 1, 1)).build()),
      ],
    );
    final plan = ImportPlan(
      document: document,
      profile: const ProjectProfile(),
    );
    expect(plan.triangleCount, document.triangleCount);
  });

  group('ImportPlan', () {
    test('warningCount reads the document\'s own warnings', () {
      final plan = ImportPlan(
        document: _documentWithCuboid(
          Vector3(1, 1, 1),
          warnings: <String>['a', 'b', 'c'],
        ),
        profile: const ProjectProfile(),
      );
      expect(plan.warningCount, 3);
    });

    test('exceedsTriangleBudget is false comfortably under the profile\'s '
        'own limit', () {
      final plan = ImportPlan(
        document: _documentWithCuboid(Vector3(1, 1, 1)),
        profile: const ProjectProfile(),
      );
      expect(plan.exceedsTriangleBudget, isFalse);
    });

    test('exceedsTriangleBudget is true against a profile whose limit the '
        'model is over', () {
      final plan = ImportPlan(
        document: _documentWithCuboid(Vector3(1, 1, 1)),
        profile: const ProjectProfile(maxTriangles: 4),
      );
      expect(plan.exceedsTriangleBudget, isTrue);
    });

    test('a .stl in millimetres, opened with "mm" chosen, reads its bounds '
        'back in metres', () {
      // A 2000×2000×2000 cuboid — a two-metre cube if it is really
      // millimetres, and the row's own worked example.
      final document = _documentWithCuboid(Vector3(2000, 2000, 2000));
      final rawBounds = document.computeBounds();

      final plan = ImportPlan(
        document: document,
        profile: const ProjectProfile(),
        unit: ImportUnit.millimetres,
      );

      final scaled = plan.scaledBounds;
      expect(scaled.min.x, closeTo(rawBounds.min.x * 0.001, 1e-9));
      expect(scaled.min.y, closeTo(rawBounds.min.y * 0.001, 1e-9));
      expect(scaled.min.z, closeTo(rawBounds.min.z * 0.001, 1e-9));
      expect(scaled.max.x, closeTo(rawBounds.max.x * 0.001, 1e-9));
      // The cuboid is 2000 units wide; read as millimetres that is 2 metres,
      // so a corner at +1000 reads as +1.
      expect(scaled.max.x, closeTo(1.0, 1e-9));
    });

    test('a document already in metres is left exactly as it was', () {
      final document = _documentWithCuboid(Vector3(2, 2, 2));
      final plan = ImportPlan(
        document: document,
        profile: const ProjectProfile(),
      );
      final raw = document.computeBounds();
      final scaled = plan.scaledBounds;
      expect(scaled.min.x, closeTo(raw.min.x, 1e-9));
      expect(scaled.max.x, closeTo(raw.max.x, 1e-9));
    });

    test('optionsWith resolves the chosen unit and up axis into '
        'ImportOptions', () {
      final plan = ImportPlan(
        document: _documentWithCuboid(Vector3(1, 1, 1)),
        profile: const ProjectProfile(),
        unit: ImportUnit.centimetres,
      );
      final options = plan.optionsWith(upAxis: UpAxis.z);
      expect(options.scale, 0.01);
      expect(options.upAxis, UpAxis.z);
    });

    test('exceedsMobileTriangleBudget is true over the mobile preset even '
        'when the active profile is desktop', () {
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[
          for (var i = 0; i < ProjectProfile.mobile.maxTriangles ~/ 12 + 1; i++)
            ModelSurface(mesh: CuboidShape(size: Vector3(1, 1, 1)).build()),
        ],
      );
      final plan = ImportPlan(
        document: document,
        profile: const ProjectProfile(), // desktop, a much wider budget
      );
      expect(
        document.triangleCount,
        greaterThan(ProjectProfile.mobile.maxTriangles),
      );
      expect(plan.exceedsMobileTriangleBudget, isTrue);
    });

    test('exceedsMobileTriangleBudget is false comfortably under the '
        'mobile preset', () {
      final plan = ImportPlan(
        document: _documentWithCuboid(Vector3(1, 1, 1)),
        profile: const ProjectProfile(),
      );
      expect(plan.exceedsMobileTriangleBudget, isFalse);
    });

    test('weld/fixNormals/triangulate default to sensible values', () {
      final plan = ImportPlan(
        document: _documentWithCuboid(Vector3(1, 1, 1)),
        profile: const ProjectProfile(),
      );
      expect(plan.weld, isTrue);
      expect(plan.fixNormals, isFalse);
      expect(plan.triangulate, isFalse);
    });
  });

  group('weldEpsilonFor', () {
    test('null (importMeshData\'s own default epsilon) when weld is on', () {
      expect(weldEpsilonFor(weld: true), isNull);
    });

    test('zero (exact duplicates only) when weld is off', () {
      expect(weldEpsilonFor(weld: false), 0.0);
    });
  });
}
