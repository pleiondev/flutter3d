/// `surfaceDeviation`: the distance a level of detail is switched by,
/// measured against a reference that does not share its shortcuts.
///
///     dart test test/simplify_error_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

MeshData _sphere({double radius = 1.0, int segments = 40, int rings = 40}) =>
    SphereShape(
      radius: radius,
      segments: segments,
      rings: rings,
    ).build(layout: VertexLayout.positionOnly);

/// Every triangle of [mesh] against [p], no tree and no widening box.
double _bruteDistance(Vector3 p, MeshData mesh) {
  final nearest = Vector3.zero();
  var best = double.infinity;
  for (var t = 0; t < mesh.triangleCount; t++) {
    closestPointOnTriangle(
      p,
      mesh.positionAt(mesh.indices[t * 3]),
      mesh.positionAt(mesh.indices[t * 3 + 1]),
      mesh.positionAt(mesh.indices[t * 3 + 2]),
      nearest,
    );
    best = math.min(best, nearest.distanceTo(p));
  }
  return best;
}

void main() {
  test('a mesh against itself deviates by nothing', () {
    final sphere = _sphere();
    expect(surfaceDeviation(sphere, sphere), closeTo(0.0, 1e-6));
  });

  test('a sphere against a larger copy deviates by the difference in '
      'radius', () {
    // Each vertex of one is a tenth of a unit straight out from a vertex of
    // the other, and the nearest point of the other surface is at most a
    // chord's sagitta closer than that.
    final deviation = surfaceDeviation(_sphere(), _sphere(radius: 1.1));
    expect(deviation, closeTo(0.1, 0.005));
  });

  test('a sphere cut to a tenth measures within a small factor of a brute '
      'force and analytic reference, where the simplifier\'s bound does '
      'not', () {
    final sphere = _sphere();
    final cut = simplifyMeshWithAttributesMeasured(
      sphere,
      targetTriangleCount: sphere.triangleCount ~/ 10,
    );
    final measured = surfaceDeviation(sphere, cut.mesh);

    // One way, brute force: every original vertex against every simplified
    // triangle.
    var reference = 0.0;
    for (var v = 0; v < sphere.vertexCount; v++) {
      reference = math.max(
        reference,
        _bruteDistance(sphere.positionAt(v), cut.mesh),
      );
    }
    // The other way, analytically: a dense lattice over every simplified
    // triangle, each point's distance to the unit sphere the original
    // tessellates. The tessellation sits inside the sphere by at most its own
    // sagitta, which bounds how far the two references can disagree.
    const steps = 8;
    for (var t = 0; t < cut.mesh.triangleCount; t++) {
      final a = cut.mesh.positionAt(cut.mesh.indices[t * 3]);
      final b = cut.mesh.positionAt(cut.mesh.indices[t * 3 + 1]);
      final c = cut.mesh.positionAt(cut.mesh.indices[t * 3 + 2]);
      for (var i = 0; i <= steps; i++) {
        for (var j = 0; j <= steps - i; j++) {
          final p =
              a +
              (b - a) * (i / steps).toDouble() +
              (c - a) * (j / steps).toDouble();
          reference = math.max(reference, (p.length - 1.0).abs());
        }
      }
    }
    final sagitta = 1.0 - math.cos(math.pi / 40);

    expect(measured, greaterThan(0.0));
    expect(measured, greaterThan(reference * 0.8 - sagitta));
    expect(measured, lessThan(reference * 1.25 + sagitta));
    // The quadric bound the simplifier reports is several times larger, which
    // is why a level is not switched by it.
    expect(cut.error, greaterThan(measured * 2));
  });

  test('a mesh with triangles against one with none is infinitely far', () {
    final empty = MeshData(
      layout: VertexLayout.positionOnly,
      vertices: _sphere().vertices,
      indices: _sphere().indices.sublist(0, 0),
    );
    expect(surfaceDeviation(_sphere(), empty), double.infinity);
    expect(surfaceDeviation(empty, empty), 0.0);
  });
}
