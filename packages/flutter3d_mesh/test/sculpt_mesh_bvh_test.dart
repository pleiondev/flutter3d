/// `pro-sc-04`'s own acceptance: `SculptMeshBvh.raycast` matches a brute
/// force over every triangle, and `refit` after a stroke matches a fresh
/// rebuild — "рейкаст = перебор; refit = перестроение".
///
///     dart test test/sculpt_mesh_bvh_test.dart
library;

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// A `cols` × `rows` flat grid in the XZ plane, `y = 0` — small enough that
/// scanning every triangle for the brute-force oracle costs nothing to
/// write assertions over.
EditMesh _grid({int cols = 8, int rows = 8}) {
  final builder = EditMeshBuilder();
  final vertices = <List<int>>[];
  for (var j = 0; j <= rows; j++) {
    final row = <int>[];
    for (var i = 0; i <= cols; i++) {
      row.add(builder.addVertex(Vector3(i * 1.0, 0, j * 1.0)));
    }
    vertices.add(row);
  }
  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < cols; i++) {
      builder.addFace(<int>[
        vertices[j][i],
        vertices[j][i + 1],
        vertices[j + 1][i + 1],
        vertices[j + 1][i],
      ]);
    }
  }
  return builder.build();
}

/// The nearest triangle [ray] hits, scanning every one of [mesh]'s own
/// triangles directly — the oracle `pro-sc-04`'s own acceptance names.
({int triangle, double distance})? _bruteForceRaycast(
  SculptMesh mesh,
  Ray ray,
) {
  var best = double.infinity;
  var found = -1;
  final a = Vector3.zero();
  final b = Vector3.zero();
  final c = Vector3.zero();
  final triangles = mesh.triangles;
  for (var t = 0; t < triangles.length ~/ 3; t++) {
    mesh.positionOf(triangles[t * 3], a);
    mesh.positionOf(triangles[t * 3 + 1], b);
    mesh.positionOf(triangles[t * 3 + 2], c);
    final hit = rayTriangle(ray, a, b, c);
    if (hit >= 0 && hit < best) {
      best = hit;
      found = t;
    }
  }
  return found < 0 ? null : (triangle: found, distance: best);
}

void main() {
  group('SculptMeshBvh.raycast', () {
    test('matches a brute-force scan over every triangle', () {
      final mesh = SculptMesh.fromEditMesh(_grid());
      final bvh = SculptMeshBvh.build(mesh);

      final rays = <Ray>[
        // Off any quad's own diagonal (the line `z == x` within a unit
        // cell, wherever `EditMesh.fromFaces`'s own triangulator happens to
        // cut it) — a ray on that line lands exactly on the edge two
        // triangles share, where either is an equally correct, tied
        // answer, and a brute-force scan and a tree walk are free to break
        // the tie differently.
        Ray(Vector3(3.3, 5, 3.7), Vector3(0, -1, 0)),
        Ray(Vector3(0.3, 5, 0.7), Vector3(0, -1, 0)),
        Ray(Vector3(7.3, 5, 7.7), Vector3(0, -1, 0)),
        Ray(Vector3(3.3, 5, 3.7), Vector3(0, 1, 0)), // pointed away: no hit
        Ray(Vector3(100, 5, 100), Vector3(0, -1, 0)), // off the grid
      ];

      for (final ray in rays) {
        final expected = _bruteForceRaycast(mesh, ray);
        final actual = bvh.raycast(ray);
        if (expected == null) {
          expect(actual, isNull, reason: 'ray $ray');
        } else {
          expect(actual, isNotNull, reason: 'ray $ray');
          expect(actual!.triangle, expected.triangle, reason: 'ray $ray');
          expect(
            actual.distance,
            closeTo(expected.distance, 1e-6),
            reason: 'ray $ray',
          );
        }
      }
    });
  });

  group('SculptMeshBvh.refit', () {
    test('after a stroke, matches a fresh rebuild', () {
      final mesh = SculptMesh.fromEditMesh(_grid());
      final bvh = SculptMeshBvh.build(mesh);

      mesh.applyBrush(
        center: Vector3(3.5, 0, 3.5),
        radius: 2.0,
        displace: (int vertex, Vector3 position, double falloff) =>
            position + Vector3(0, falloff * 3.0, 0),
      );
      bvh.refit();

      final rebuilt = SculptMeshBvh.build(mesh);

      // The same rays the raycast test above uses, now over the bulged
      // mesh: a refit that left stale bounds behind would disagree with a
      // fresh rebuild on exactly the rays that pass near the raised area.
      final rays = <Ray>[
        Ray(Vector3(3.3, 10, 3.7), Vector3(0, -1, 0)),
        Ray(Vector3(4.2, 10, 4.2), Vector3(0, -1, 0)),
        Ray(Vector3(0.2, 5, 0.2), Vector3(0, -1, 0)),
        Ray(Vector3(7.8, 5, 7.8), Vector3(0, -1, 0)),
      ];

      for (final ray in rays) {
        final afterRefit = bvh.raycast(ray);
        final afterRebuild = rebuilt.raycast(ray);
        if (afterRebuild == null) {
          expect(afterRefit, isNull, reason: 'ray $ray');
        } else {
          expect(afterRefit, isNotNull, reason: 'ray $ray');
          expect(
            afterRefit!.triangle,
            afterRebuild.triangle,
            reason: 'ray $ray',
          );
          expect(
            afterRefit.distance,
            closeTo(afterRebuild.distance, 1e-6),
            reason: 'ray $ray',
          );
          expect(
            afterRefit.point.x,
            closeTo(afterRebuild.point.x, 1e-6),
            reason: 'ray $ray',
          );
        }
      }
    });

    test('also matches a brute-force scan, not just the pre-stroke tree', () {
      final mesh = SculptMesh.fromEditMesh(_grid());
      final bvh = SculptMeshBvh.build(mesh);

      mesh.applyBrush(
        center: Vector3(3.5, 0, 3.5),
        radius: 2.0,
        displace: (int vertex, Vector3 position, double falloff) =>
            position + Vector3(0, falloff * 3.0, 0),
      );
      bvh.refit();

      final ray = Ray(Vector3(3.3, 10, 3.7), Vector3(0, -1, 0));
      final expected = _bruteForceRaycast(mesh, ray)!;
      final actual = bvh.raycast(ray)!;

      expect(actual.triangle, expected.triangle);
      expect(actual.distance, closeTo(expected.distance, 1e-6));
    });
  });
}
