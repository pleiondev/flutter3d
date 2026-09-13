/// `pro-rt-01`'s own acceptance: `retopologize` gives at least 70% quad
/// faces on a sphere and a torus, and shrink-wraps within 0.5% of the
/// source's own bounding-box diagonal — checked against each shape's own
/// analytic surface, not against the mesh this function itself built, so
/// the oracle cannot share a mistake with the code it is checking.
///
///     dart test test/retopologize_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The fraction of [mesh]'s own live faces with exactly four corners.
double _quadFraction(EditMesh mesh) {
  var quads = 0;
  var total = 0;
  for (var f = 0; f < mesh.faceSlotCount; f++) {
    if (!mesh.isFaceAlive(f)) continue;
    total++;
    if (mesh.valencyOf(f) == 4) quads++;
  }
  return total == 0 ? 0.0 : quads / total;
}

/// How far every live vertex of [mesh] sits from the surface [distanceToSurface]
/// describes, as a fraction of [diagonal] — the worst vertex, since the
/// acceptance is a bound every vertex has to clear, not an average.
double _worstRelativeDistance(
  EditMesh mesh,
  double Function(Vector3) distanceToSurface,
  double diagonal,
) {
  var worst = 0.0;
  final p = Vector3.zero();
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    if (!mesh.isVertexAlive(v)) continue;
    mesh.positionOf(v, p);
    final relative = distanceToSurface(p).abs() / diagonal;
    if (relative > worst) worst = relative;
  }
  return worst;
}

void main() {
  group('retopologize', () {
    test('a sphere: ≥70% quads, shrink-wrapped within 0.5% of the diagonal', () {
      const radius = 1.0;
      final source = const ParametricSphere(
        radius: radius,
        segments: 48,
        rings: 24,
      ).toEditMesh();
      final diagonal = radius * 2 * math.sqrt(3); // a cube around the sphere

      final result = retopologize(source, targetQuads: 200);

      final quadFraction = _quadFraction(result);
      // ignore: avoid_print
      print('sphere: ${(quadFraction * 100).toStringAsFixed(1)}% quads');
      expect(quadFraction, greaterThanOrEqualTo(0.70));

      double distanceToSphere(Vector3 p) => p.length - radius;
      final worst = _worstRelativeDistance(result, distanceToSphere, diagonal);
      // ignore: avoid_print
      print('sphere: worst relative distance ${(worst * 100).toStringAsFixed(3)}%');
      expect(worst, lessThan(0.005));
    });

    test('a torus: ≥70% quads, shrink-wrapped within 0.5% of the diagonal', () {
      const majorRadius = 1.0;
      const tubeRadius = 0.4;
      final source = const ParametricTorus(
        radius: majorRadius,
        tubeRadius: tubeRadius,
        segments: 48,
        tubeSegments: 24,
      ).toEditMesh();
      // A box around the torus: ±(major + tube) in X/Z, ±tube in Y.
      final half = Vector3(
        majorRadius + tubeRadius,
        tubeRadius,
        majorRadius + tubeRadius,
      );
      final diagonal = (half * 2).length;

      final result = retopologize(source, targetQuads: 200);

      final quadFraction = _quadFraction(result);
      // ignore: avoid_print
      print('torus: ${(quadFraction * 100).toStringAsFixed(1)}% quads');
      expect(quadFraction, greaterThanOrEqualTo(0.70));

      double distanceToTorus(Vector3 p) {
        final d = math.sqrt(p.x * p.x + p.z * p.z);
        final toTubeCentre = math.sqrt(
          (d - majorRadius) * (d - majorRadius) + p.y * p.y,
        );
        return toTubeCentre - tubeRadius;
      }

      final worst = _worstRelativeDistance(result, distanceToTorus, diagonal);
      // ignore: avoid_print
      print('torus: worst relative distance ${(worst * 100).toStringAsFixed(3)}%');
      expect(worst, lessThan(0.005));
    });

    test('a mesh already at or under the target is returned close to as-is', () {
      final source = const ParametricSphere(segments: 8, rings: 4).toEditMesh();
      final result = retopologize(source, targetQuads: 1000);

      // Nothing to simplify away, but quadrangulation still runs.
      expect(result.vertexSlotCount, greaterThan(0));
      expect(_quadFraction(result), greaterThan(0.0));
    });
  });
}
