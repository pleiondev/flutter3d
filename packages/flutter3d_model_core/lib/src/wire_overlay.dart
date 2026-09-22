/// `mcp-08n`'s fourth mode: an object's own polygon edges as solid geometry.
///
/// **Why this is geometry and not a line pipeline.** `mcp-08n` asks for four
/// render modes and shipped with three, and the reason its own row gives is
/// that `wireframe` waited on `view-07`'s edge drawing — `MeshData
/// .edgeIndices()`, `DeviceMesh.upload(withEdges:)`, a `MeshWireVertex`
/// stage, a line topology in six fragment stages across four backends. That
/// row is phase 2 and starting it here would be working out of the order the
/// plan chose.
///
/// It is also not what this mode needs. A wire drawn as a *thin solid* needs
/// no topology any backend does not already have: every edge becomes a
/// three-sided prism, and the renderer draws triangles the way it does for
/// everything else. It costs triangles — six per edge — which is the right
/// trade for a still picture an agent asks for one frame at a time, and the
/// wrong one for a viewport drawing it sixty times a second. That is exactly
/// why this lives beside `renderProject` and not in the engine: `view-07`
/// is still the answer for the live viewport, and this is the answer for a
/// headless frame.
///
/// **The edges are the document's, not the triangulation's**, and that is
/// the point of the mode. `EditMesh` holds real n-gons; the renderer sees
/// them fanned into triangles. A wireframe built from the drawn triangles
/// shows a hexagon as six triangles with three diagonals across it, which is
/// the picture of the triangulator rather than of the model. This walks the
/// half-edges of each live face, so a hexagon has six wires and an agent
/// looking at the frame sees the n-gon its readiness report warned about.
library;

import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

/// How thick a wire is, as a fraction of the mesh's own bounding diagonal.
///
/// Relative rather than absolute because the same number has to read on a
/// two-metre character and a two-centimetre bolt, and neither knows about the
/// other. Measured by eye against `case4.glb`'s robot at 512 × 512: a
/// thousandth of the diagonal is about one pixel there, and this is three of
/// them — thin enough to leave the surface visible between wires, thick
/// enough to survive the rasteriser at a quarter that size.
const double wireThickness = 0.003;

/// The polygon edges of [mesh] as a solid mesh of three-sided prisms.
///
/// Returns null when there is nothing to draw: no live face, or a mesh so
/// small that every edge is shorter than the thickness a wire would need.
/// Null rather than an empty [MeshData] because `DeviceMesh.upload` of an
/// empty mesh is a draw call that renders nothing, and a caller deciding
/// whether to add a node is better served by being told there is no node to
/// add.
MeshData? wireMeshFor(EditMesh mesh, {double thickness = wireThickness}) {
  final edges = polygonEdgesOf(mesh);
  if (edges.isEmpty) return null;

  final radius = _radiusFor(mesh, thickness);
  if (radius <= 0.0) return null;

  final builder = MeshBuilder(
    VertexLayout.standard,
    reserveVertices: edges.length * 6,
    reserveIndices: edges.length * 18,
  );
  final from = Vector3.zero();
  final to = Vector3.zero();
  for (final (int a, int b) in edges) {
    mesh.positionOf(a, from);
    mesh.positionOf(b, to);
    _addWire(builder, from, to, radius);
  }
  if (builder.indexCount == 0) return null;
  return builder.build();
}

/// Every edge of every live face of [mesh], each once, as a pair of vertex
/// indices with the smaller first.
///
/// Walked over half-edges rather than read off a twin table: a boundary edge
/// has no twin, and an edge between two faces is reached twice — so the pair
/// is normalised and de-duplicated, which handles both without either being a
/// special case.
List<(int, int)> polygonEdgesOf(EditMesh mesh) {
  final seen = <int>{};
  final edges = <(int, int)>[];
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    mesh.forEachHalfEdge(face, (int half) {
      final int a = mesh.originOf(half);
      final int b = mesh.originOf(mesh.nextOf(half));
      if (a == b) return;
      final int low = a < b ? a : b;
      final int high = a < b ? b : a;
      // One integer key rather than a set of records: a record's own equality
      // would do, and this is a hot loop over every corner of every face.
      final int key = low * mesh.vertexSlotCount + high;
      if (!seen.add(key)) return;
      edges.add((low, high));
    });
  }
  return edges;
}

/// [thickness] of the mesh's own bounding diagonal, or zero when the mesh has
/// no extent at all to take a fraction of.
double _radiusFor(EditMesh mesh, double thickness) {
  // Mutated in place by `Vector3.min`/`Vector3.max` below, which is why they
  // are final and still accumulate.
  final Vector3 minimum = Vector3.all(double.infinity);
  final Vector3 maximum = Vector3.all(-double.infinity);
  final at = Vector3.zero();
  var alive = 0;
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
    if (!mesh.isVertexAlive(vertex)) continue;
    alive++;
    mesh.positionOf(vertex, at);
    Vector3.min(minimum, at, minimum);
    Vector3.max(maximum, at, maximum);
  }
  if (alive == 0) return 0.0;
  final double diagonal = (maximum - minimum).length;
  if (diagonal <= 0.0) return 0.0;
  return diagonal * thickness;
}

/// One edge as a three-sided prism from [from] to [to].
///
/// Three sides and not four: a wire is looked at, not measured, and three
/// gives a stick that reads as round from every angle for two triangles less
/// per edge than a quad tube does. Capped at neither end — an edge meets
/// other edges at both, so the ends are inside the joint.
void _addWire(MeshBuilder builder, Vector3 from, Vector3 to, double radius) {
  final along = to - from;
  final double length = along.length;
  // Shorter than it is thick: drawing it would be a blob at a vertex rather
  // than a wire between two, and a zero-length edge has no direction to build
  // a ring around at all.
  if (length <= radius) return;
  along.scale(1.0 / length);

  // Any axis not parallel to the edge. Picked off the edge's own smallest
  // component, so the cross product below is never near zero — choosing a
  // fixed axis would degenerate for every edge that happened to run along it.
  final Vector3 helper = along.x.abs() < 0.9
      ? Vector3(1.0, 0.0, 0.0)
      : Vector3(0.0, 1.0, 0.0);
  final Vector3 u = along.cross(helper)..normalize();
  final Vector3 v = along.cross(u)..normalize();

  final ring = <Vector3>[
    for (var corner = 0; corner < 3; corner++)
      () {
        final double angle = corner * 2.0 * math.pi / 3.0;
        return (u * math.cos(angle)) + (v * math.sin(angle));
      }(),
  ];

  final starts = <int>[];
  final ends = <int>[];
  for (var corner = 0; corner < 3; corner++) {
    final Vector3 outward = ring[corner];
    starts.add(
      builder.addVertex(
        position: from + outward * radius,
        normal: outward.clone(),
      ),
    );
    ends.add(
      builder.addVertex(
        position: to + outward * radius,
        normal: outward.clone(),
      ),
    );
  }
  for (var corner = 0; corner < 3; corner++) {
    final int next = (corner + 1) % 3;
    builder
      ..addTriangle(starts[corner], ends[corner], ends[next])
      ..addTriangle(starts[corner], ends[next], starts[next]);
  }
}
