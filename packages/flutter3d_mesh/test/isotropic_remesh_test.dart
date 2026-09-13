/// Isotropic remeshing — split, collapse, flip, tangential smoothing — over
/// `EditMesh`. `mesh-73`'s own spike.
///
///     dart test test/isotropic_remesh_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Runs [body] as one step of history.
void edit(EditMesh mesh, void Function() body) {
  mesh.beginStep();
  body();
  mesh.endStep();
}

/// A triangulated UV sphere — `ParametricSphere` hands over rings of quads
/// with a fan at each pole, and remeshing wants pure triangles going in.
EditMesh triangulatedSphere({
  double radius = 1,
  int segments = 24,
  int rings = 12,
}) {
  final mesh = ParametricSphere(
    radius: radius,
    segments: segments,
    rings: rings,
  ).toEditMesh();
  edit(
    mesh,
    () => triangulateFaces(mesh, Selection.all(mesh, ElementLevel.face)),
  );
  return mesh;
}

/// Scales every vertex of [mesh] by [by], in place.
void stretch(EditMesh mesh, Vector3 by) {
  edit(mesh, () {
    for (var v = 0; v < mesh.vertexSlotCount; v++) {
      if (!mesh.isVertexAlive(v)) continue;
      final p = mesh.positionOf(v);
      mesh.moveVertex(v, Vector3(p.x * by.x, p.y * by.y, p.z * by.z));
    }
  });
}

void main() {
  group('triangleAspectRatio', () {
    test('an equilateral triangle reads 1', () {
      final ratio = triangleAspectRatio(
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0.5, 0.8660254, 0),
      );
      expect(ratio, closeTo(1.0, 1e-3));
    });

    test('a degenerate triangle reads infinite rather than throwing', () {
      final ratio = triangleAspectRatio(
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(2, 0, 0),
      );
      expect(ratio, equals(double.infinity));
    });

    test('a sliver reads far worse than equilateral', () {
      final sliver = triangleAspectRatio(
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0.5, 0.02, 0),
      );
      expect(sliver, greaterThan(10));
    });
  });

  group('MeshQualityStats.of', () {
    test('refuses a mesh that still has non-triangle faces', () {
      final cube = EditMesh.cuboid();
      expect(() => MeshQualityStats.of(cube), throwsArgumentError);
    });

    test('reads a real sphere without throwing', () {
      final stats = MeshQualityStats.of(triangulatedSphere());
      expect(stats.triangleCount, greaterThan(0));
      expect(stats.edgeCount, greaterThan(0));
      expect(stats.meanEdgeLength, greaterThan(0));
    });
  });

  group('isotropicRemesh', () {
    test('rejects a non-positive target edge length', () {
      final mesh = triangulatedSphere();
      expect(
        () => isotropicRemesh(mesh, targetEdgeLength: 0),
        throwsArgumentError,
      );
    });

    test('rejects fewer than one iteration', () {
      final mesh = triangulatedSphere();
      expect(
        () => isotropicRemesh(mesh, targetEdgeLength: 0.3, iterations: 0),
        throwsArgumentError,
      );
    });

    test(
      'shrinks edge-length variance on a UV sphere, keeping it a topological '
      'sphere',
      () {
        final mesh = triangulatedSphere(radius: 1, segments: 24, rings: 12);
        final before = MeshQualityStats.of(mesh);
        // A UV sphere's triangles shrink toward the poles — real, non-trivial
        // non-uniformity to remesh away, not a synthetic perturbation.
        expect(before.edgeLengthCv, greaterThan(0.1));

        final (remeshed, report) = isotropicRemesh(
          mesh,
          targetEdgeLength: before.meanEdgeLength,
          iterations: 8,
        );
        remeshed.validate();

        printOnFailure(report.toString());
        expect(report.after.edgeLengthCv, lessThan(before.edgeLengthCv * 0.7));
        expect(
          report.after.meanAspectRatio,
          lessThanOrEqualTo(before.meanAspectRatio),
        );
        expect(remeshed.eulerCharacteristic, equals(2));
        expect(report.edgeSplits, greaterThan(0));
        expect(report.edgeFlips, greaterThan(0));
      },
    );

    test('shrinks mean and max aspect ratio on a sphere stretched into an '
        'ellipsoid', () {
      final mesh = triangulatedSphere(radius: 1, segments: 24, rings: 12);
      stretch(mesh, Vector3(4, 1, 1));
      final before = MeshQualityStats.of(mesh);
      // The stretch is what makes this "deliberately bad": elongated
      // triangles along the stretched axis, not the sphere's own pole
      // convergence.
      expect(before.meanAspectRatio, greaterThan(1.5));

      final (remeshed, report) = isotropicRemesh(
        mesh,
        targetEdgeLength: before.meanEdgeLength,
        iterations: 8,
      );
      remeshed.validate();

      printOnFailure(report.toString());
      expect(
        report.after.meanAspectRatio,
        lessThan(before.meanAspectRatio * 0.6),
      );
      expect(
        report.after.maxAspectRatio,
        lessThan(before.maxAspectRatio * 0.6),
      );
      expect(remeshed.eulerCharacteristic, equals(2));
    });

    test('more iterations converge rather than diverge', () {
      final mesh = triangulatedSphere(radius: 1, segments: 24, rings: 12);
      final target = MeshQualityStats.of(mesh).meanEdgeLength;

      final (afterFew, fewReport) = isotropicRemesh(
        mesh,
        targetEdgeLength: target,
        iterations: 2,
      );
      final fewCv = fewReport.after.edgeLengthCv;

      final (afterMore, moreReport) = isotropicRemesh(
        afterFew,
        targetEdgeLength: target,
        iterations: 6,
      );
      afterMore.validate();

      expect(moreReport.after.edgeLengthCv, lessThanOrEqualTo(fewCv));
    });
  });
}
