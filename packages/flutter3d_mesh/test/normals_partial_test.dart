/// `MeshNormals.rebuildAround` — `pro-sc-10n`: a stroke pays for the fans it
/// touched, and the answer is the one a whole rebuild gives.
///
/// **Written by breaking what it covers** (`ARCHITECTURE.md` rule 6.3). The
/// mutation: drop the backwards half of `_forEachCornerAt`'s fan walk, which
/// is exactly the mistake a fan gathered with `EditMesh.neighborsOf` would
/// make. Two tests go red and seven stay green — *a vertex on the open edge*
/// and *a whole band of vertices*, the two where a fan really does run out
/// partway round. The interior, closed-mesh and sheet-corner cases pass
/// either way, which is why a file with only those in it would have shipped
/// the bug.
///
///     dart test test/normals_partial_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// An `n`×`n` grid of quads in the XZ plane, gently domed so no two faces are
/// coplanar — a flat sheet would agree with itself whatever the fans came out
/// as, which is exactly the mistake this file exists to catch. It has an open
/// edge all the way round, which is the other half of why.
EditMesh _grid(int n) {
  final points = <Vector3>[];
  for (var z = 0; z <= n; z++) {
    for (var x = 0; x <= n; x++) {
      final u = x / n - 0.5;
      final v = z / n - 0.5;
      points.add(Vector3(u, 0.4 * math.cos(u * 3) * math.cos(v * 3), v));
    }
  }
  final faces = <List<int>>[];
  for (var z = 0; z < n; z++) {
    for (var x = 0; x < n; x++) {
      final at = z * (n + 1) + x;
      faces.add(<int>[at, at + 1, at + n + 2, at + n + 1]);
    }
  }
  return EditMesh.fromFaces(points, faces);
}

/// Every corner normal and every face normal, as one flat list.
List<double> _snapshot(MeshNormals normals, EditMesh mesh) => <double>[
  for (var face = 0; face < mesh.faceSlotCount; face++)
    if (mesh.isFaceAlive(face)) ...<double>[
      normals.faceNormals[face * 3],
      normals.faceNormals[face * 3 + 1],
      normals.faceNormals[face * 3 + 2],
    ],
  for (var half = 0; half < mesh.halfEdgeSlotCount; half++) ...<double>[
    normals.cornerNormals[half * 3],
    normals.cornerNormals[half * 3 + 1],
    normals.cornerNormals[half * 3 + 2],
  ],
];

/// Moves [vertices] straight up by [by].
void _lift(EditMesh mesh, Iterable<int> vertices, double by) {
  mesh.beginStep();
  final at = Vector3.zero();
  for (final int vertex in vertices) {
    mesh.positionOf(vertex, at);
    mesh.moveVertex(vertex, Vector3(at.x, at.y + by, at.z));
  }
}

/// Which vertex sits nearest [where].
int _nearest(EditMesh mesh, Vector3 where) {
  var best = -1;
  var bestDistance = double.infinity;
  final at = Vector3.zero();
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
    if (!mesh.isVertexAlive(vertex)) continue;
    mesh.positionOf(vertex, at);
    final distance = at.distanceToSquared(where);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = vertex;
    }
  }
  return best;
}

void main() {
  group('rebuildAround gives what build gives', () {
    test('a vertex in the middle of a sheet', () {
      final mesh = _grid(8);
      final partial = MeshNormals()..build(mesh);

      final moved = <int>[_nearest(mesh, Vector3(0, 0, 0))];
      _lift(mesh, moved, 0.3);

      partial.rebuildAround(mesh, moved);
      final whole = MeshNormals()..build(mesh);

      expect(_snapshot(partial, mesh), _snapshot(whole, mesh));
    });

    test('a vertex on the open edge, where half the fan is unreachable', () {
      // The case the row was written for: rotating one way round a boundary
      // vertex stops at the edge with no twin, and a fan rebuilt from what
      // that walk saw is averaged over half its faces — a crease nobody put
      // there, on the silhouette, where it shows.
      final mesh = _grid(8);
      final partial = MeshNormals()..build(mesh);

      final moved = <int>[_nearest(mesh, Vector3(-0.5, 0, 0))];
      _lift(mesh, moved, 0.3);

      partial.rebuildAround(mesh, moved);
      final whole = MeshNormals()..build(mesh);

      expect(_snapshot(partial, mesh), _snapshot(whole, mesh));
    });

    test('a corner of the sheet, where the fan is a quarter turn', () {
      final mesh = _grid(8);
      final partial = MeshNormals()..build(mesh);

      final moved = <int>[_nearest(mesh, Vector3(-0.5, 0, -0.5))];
      _lift(mesh, moved, 0.3);

      partial.rebuildAround(mesh, moved);
      final whole = MeshNormals()..build(mesh);

      expect(_snapshot(partial, mesh), _snapshot(whole, mesh));
    });

    test('a closed mesh, where every fan comes all the way round', () {
      final mesh = EditMesh.cuboid(size: Vector3(2, 2, 2));
      final partial = MeshNormals()..build(mesh);

      final moved = <int>[0, 1];
      _lift(mesh, moved, 0.5);

      partial.rebuildAround(mesh, moved);
      final whole = MeshNormals()..build(mesh);

      expect(_snapshot(partial, mesh), _snapshot(whole, mesh));
    });

    test('a whole band of vertices, the shape a real stroke leaves', () {
      final mesh = _grid(10);
      final partial = MeshNormals()..build(mesh);

      final at = Vector3.zero();
      final moved = <int>[];
      for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
        if (!mesh.isVertexAlive(vertex)) continue;
        mesh.positionOf(vertex, at);
        if (at.z.abs() < 0.12) moved.add(vertex);
      }
      expect(moved, isNotEmpty);
      _lift(mesh, moved, 0.25);

      partial.rebuildAround(mesh, moved);
      final whole = MeshNormals()..build(mesh);

      expect(_snapshot(partial, mesh), _snapshot(whole, mesh));
    });

    test('a sharp edge stays sharp through a partial rebuild', () {
      final mesh = _grid(6)..beginStep();
      // One row of edges marked sharp: the fans either side of it must stay
      // two fans, which a regrouping that forgot the flag would merge.
      for (var half = 0; half < mesh.halfEdgeSlotCount; half++) {
        final face = mesh.faceOf(half);
        if (face == EditMesh.none || !mesh.isFaceAlive(face)) continue;
        final a = Vector3.zero();
        final b = Vector3.zero();
        mesh.positionOf(mesh.originOf(half), a);
        mesh.positionOf(mesh.originOf(mesh.nextOf(half)), b);
        if (a.z.abs() < 1e-6 && b.z.abs() < 1e-6) {
          mesh.setEdgeFlag(half, EdgeFlags.sharp, on: true);
        }
      }
      mesh.endStep();
      final partial = MeshNormals()..build(mesh);

      final moved = <int>[_nearest(mesh, Vector3(0, 0, 0))];
      _lift(mesh, moved, 0.3);

      partial.rebuildAround(mesh, moved);
      final whole = MeshNormals()..build(mesh);

      expect(_snapshot(partial, mesh), _snapshot(whole, mesh));
    });
  });

  group('rebuildAround pays for what it touched', () {
    test('one vertex of a large sheet costs a ring, not the sheet', () {
      final mesh = _grid(40); // 1600 quads, 6400 corners
      final normals = MeshNormals()..build(mesh);

      var liveCorners = 0;
      for (var face = 0; face < mesh.faceSlotCount; face++) {
        if (!mesh.isFaceAlive(face)) continue;
        mesh.forEachHalfEdge(face, (int _) => liveCorners++);
      }

      final moved = <int>[_nearest(mesh, Vector3(0, 0, 0))];
      _lift(mesh, moved, 0.2);
      final rebuilt = normals.rebuildAround(mesh, moved);

      // One interior vertex of a quad grid: four faces, nine vertices between
      // them, and the fans at those nine. Well under a fiftieth of the sheet.
      expect(rebuilt, lessThan(liveCorners ~/ 50));
      expect(rebuilt, greaterThan(0));
    });

    test('a mesh that is not the one the last build saw gets the lot', () {
      // A partial rebuild reads `_previous`, filled for the loops the last
      // build walked. Slot counts that do not match are the cheap, certain
      // sign that those loops are not these ones — a `MeshNormals` handed a
      // different mesh, or the same one after an edit that added geometry.
      final small = _grid(4);
      final normals = MeshNormals()..build(small);

      final large = _grid(5);
      var liveCorners = 0;
      for (var face = 0; face < large.faceSlotCount; face++) {
        if (!large.isFaceAlive(face)) continue;
        large.forEachHalfEdge(face, (int _) => liveCorners++);
      }

      expect(normals.rebuildAround(large, <int>[1]), liveCorners);
      expect(
        _snapshot(normals, large),
        _snapshot(MeshNormals()..build(large), large),
      );
    });

    test('the ring it reports is the rows a buffer has to be refilled', () {
      // A partial upload that refilled only what moved would leave a seam of
      // old lighting one vertex wide around the stroke: the vertices next to
      // a moved one share a face with it, so their fans moved too.
      final mesh = _grid(6);
      final plan = MeshLayoutPlan()..build(mesh);

      final moved = <int>[_nearest(mesh, Vector3(0, 0, 0))];
      _lift(mesh, moved, 0.2);

      final touched = <int>{};
      plan.normals.rebuildAround(mesh, moved, touched: touched);

      // Nine vertices of a quad grid: the one that moved and the eight round
      // it, which is every vertex of the four faces it belongs to.
      expect(touched, hasLength(9));
      expect(touched, containsAll(moved));

      // And every one of them has rows in the plan, so refilling them is a
      // call somebody can actually make.
      final buffer = plan.rows();
      expect(plan.fillVerticesOf(mesh, buffer, touched), greaterThan(8));
    });

    test('moving nothing rebuilds nothing', () {
      final mesh = _grid(4);
      final normals = MeshNormals()..build(mesh);
      expect(normals.rebuildAround(mesh, const <int>[]), 0);
    });
  });
}
