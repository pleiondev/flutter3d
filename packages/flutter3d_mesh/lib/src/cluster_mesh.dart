/// `C9`: a huge static mesh — a scan, a CAD part — cut into clusters of a
/// few thousand triangles the scene pass can cull one by one.
///
/// **Operates on `MeshData`, like the simplifier.** The splitter reads a
/// finished mesh and writes the same mesh with its triangles reordered and a
/// `MeshClusters` table beside them; no vertex moves, none is added, and the
/// index buffer is the same triangles in a different order. So everything
/// that does not read the table — a shadow pass, an older `.f3d` reader, the
/// glTF writer — still has the whole mesh.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';

/// [mesh] with its triangles grouped into clusters of at most [maxTriangles],
/// in cluster order, and `MeshData.clusters` describing the runs.
///
/// **Grown across shared vertices, one triangle at a time.** A cluster starts
/// from the first unclaimed triangle along a Morton curve through the
/// triangles' centres and takes, of the unclaimed triangles touching it, the
/// one nearest its centre that also turns least from its average normal. Near
/// keeps the box small, so frustum and occlusion tests reject it early; turned
/// least keeps the cone narrow, so it faces away from the eye over as wide a
/// range of views as the surface allows. Vertices are matched by position, not
/// by index, because a scan's UV seams split vertices that are one point on
/// the surface.
///
/// **Stops on a fold once it is big enough.** Past [minTriangles], a cluster
/// whose best candidate turns more than [foldAngle] (radians) from its axis
/// ends there: the fold is the edge of a region that faces one way, and taking
/// it would give the cluster a cone that never culls. Below [minTriangles] it
/// keeps growing, and when nothing touching it is left — an island of scan
/// noise — it takes the next unclaimed triangles along the curve, so a mesh of
/// a thousand fragments is not a thousand clusters.
///
/// Triangles keep their original relative order inside a cluster, and the
/// clusters are in the order they were grown. A mesh of at most
/// [maxTriangles] triangles comes back as one cluster.
MeshData clusterMesh(
  MeshData mesh, {
  int maxTriangles = 4096,
  int minTriangles = 1024,
  double foldAngle = math.pi / 4,
}) {
  if (maxTriangles < 1 || minTriangles > maxTriangles) {
    throw ArgumentError(
      'clusters of $minTriangles to $maxTriangles triangles cannot be made',
    );
  }
  final triangles = mesh.triangleCount;
  if (triangles == 0) return mesh;

  final stride = mesh.layout.floatsPerVertex;
  final position = mesh.layout.floatOffsetOf(VertexLayout.position.name);
  final vertices = mesh.vertices;
  final indices = mesh.indices;

  // Centres and unit normals, one triple per triangle; a triangle with no
  // area gets a zero normal and turns from nothing.
  final centres = Float64List(triangles * 3);
  final normals = Float64List(triangles * 3);
  var area = 0.0;
  for (var t = 0; t < triangles; t++) {
    final a = indices[t * 3] * stride + position;
    final b = indices[t * 3 + 1] * stride + position;
    final c = indices[t * 3 + 2] * stride + position;
    for (var k = 0; k < 3; k++) {
      centres[t * 3 + k] =
          (vertices[a + k] + vertices[b + k] + vertices[c + k]) / 3.0;
    }
    final ux = vertices[b] - vertices[a];
    final uy = vertices[b + 1] - vertices[a + 1];
    final uz = vertices[b + 2] - vertices[a + 2];
    final vx = vertices[c] - vertices[a];
    final vy = vertices[c + 1] - vertices[a + 1];
    final vz = vertices[c + 2] - vertices[a + 2];
    final nx = uy * vz - uz * vy;
    final ny = uz * vx - ux * vz;
    final nz = ux * vy - uy * vx;
    final length = math.sqrt(nx * nx + ny * ny + nz * nz);
    area += length * 0.5;
    if (length > 0.0) {
      normals[t * 3] = nx / length;
      normals[t * 3 + 1] = ny / length;
      normals[t * 3 + 2] = nz / length;
    }
  }

  final order = _mortonOrder(centres, triangles);
  final (vertexStart, vertexTriangles, corners) = _trianglesByPoint(mesh);

  // A distance is measured against the radius a full cluster of average
  // triangles would have, so the two terms of the score stay comparable
  // whatever units the scan is in.
  final spread = math.max(area / triangles * maxTriangles / math.pi, 1e-30);

  final claimed = Uint8List(triangles);
  // The frontier: unclaimed triangles touching the cluster growing now.
  // [queued] holds the number of the cluster that last queued each, counted
  // from one, so a triangle is queued once per cluster without a set to
  // clear.
  final queued = Int32List(triangles);
  final frontier = <int>[];
  final runs = <int>[0];
  final output = Uint32List(indices.length);
  final members = <int>[];
  var written = 0;
  var cursor = 0;

  while (true) {
    while (cursor < triangles && claimed[order[cursor]] != 0) {
      cursor++;
    }
    if (cursor == triangles) break;
    final cluster = runs.length;

    members.clear();
    frontier
      ..clear()
      ..add(order[cursor]);
    queued[order[cursor]] = cluster;
    var sumX = 0.0, sumY = 0.0, sumZ = 0.0;
    var normalX = 0.0, normalY = 0.0, normalZ = 0.0;

    while (members.length < maxTriangles) {
      if (frontier.isEmpty) {
        if (members.length >= minTriangles) break;
        // Nothing touching the cluster is left, and it is still small: the
        // next unclaimed triangle along the curve is near enough.
        while (cursor < triangles && claimed[order[cursor]] != 0) {
          cursor++;
        }
        if (cursor == triangles) break;
        frontier.add(order[cursor]);
        queued[order[cursor]] = cluster;
      }

      final count = members.length;
      final axisLength = math.sqrt(
        normalX * normalX + normalY * normalY + normalZ * normalZ,
      );
      final (ax, ay, az) = axisLength > 0.0
          ? (normalX / axisLength, normalY / axisLength, normalZ / axisLength)
          : (0.0, 0.0, 0.0);
      final (cx, cy, cz) = count == 0
          ? (0.0, 0.0, 0.0)
          : (sumX / count, sumY / count, sumZ / count);

      var best = -1;
      var bestScore = double.infinity;
      var bestTurn = 1.0;
      for (var f = 0; f < frontier.length; f++) {
        final t = frontier[f];
        final dx = centres[t * 3] - cx;
        final dy = centres[t * 3 + 1] - cy;
        final dz = centres[t * 3 + 2] - cz;
        final turn =
            normals[t * 3] * ax +
            normals[t * 3 + 1] * ay +
            normals[t * 3 + 2] * az;
        final score = count == 0
            ? 0.0
            : (dx * dx + dy * dy + dz * dz) / spread + 2.0 * (1.0 - turn);
        if (score < bestScore) {
          bestScore = score;
          best = f;
          bestTurn = turn;
        }
      }
      if (count >= minTriangles &&
          axisLength > 0.0 &&
          bestTurn < math.cos(foldAngle)) {
        break;
      }

      final t = frontier[best];
      frontier[best] = frontier.last;
      frontier.removeLast();
      claimed[t] = 1;
      members.add(t);
      sumX += centres[t * 3];
      sumY += centres[t * 3 + 1];
      sumZ += centres[t * 3 + 2];
      normalX += normals[t * 3];
      normalY += normals[t * 3 + 1];
      normalZ += normals[t * 3 + 2];

      for (var k = 0; k < 3; k++) {
        final point = corners[t * 3 + k];
        for (var s = vertexStart[point]; s < vertexStart[point + 1]; s++) {
          final next = vertexTriangles[s];
          if (claimed[next] != 0 || queued[next] == cluster) continue;
          queued[next] = cluster;
          frontier.add(next);
        }
      }
    }

    members.sort();
    for (final t in members) {
      output[written++] = indices[t * 3];
      output[written++] = indices[t * 3 + 1];
      output[written++] = indices[t * 3 + 2];
    }
    runs.add(written);
  }

  final firstIndices = Uint32List.fromList(runs);
  return MeshData(
    layout: mesh.layout,
    vertices: vertices,
    indices: output,
    morphTargets: mesh.morphTargets,
    clusters: MeshClusters.measure(
      layout: mesh.layout,
      vertices: vertices,
      indices: output,
      firstIndices: firstIndices,
    ),
  );
}

/// The triangles in the order a Morton curve through their centres visits
/// them, ten bits an axis across the mesh's bounds — close in the list is
/// close in space, which is all a seed order needs.
Int32List _mortonOrder(Float64List centres, int triangles) {
  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  var maxZ = -double.infinity;
  for (var t = 0; t < triangles; t++) {
    minX = math.min(minX, centres[t * 3]);
    minY = math.min(minY, centres[t * 3 + 1]);
    minZ = math.min(minZ, centres[t * 3 + 2]);
    maxX = math.max(maxX, centres[t * 3]);
    maxY = math.max(maxY, centres[t * 3 + 1]);
    maxZ = math.max(maxZ, centres[t * 3 + 2]);
  }
  int quantise(double value, double low, double high) => high > low
      ? ((value - low) / (high - low) * 1023).round().clamp(0, 1023)
      : 0;
  int spread(int bits) {
    var x = bits & 0x3ff;
    x = (x | (x << 16)) & 0x030000ff;
    x = (x | (x << 8)) & 0x0300f00f;
    x = (x | (x << 4)) & 0x030c30c3;
    x = (x | (x << 2)) & 0x09249249;
    return x;
  }

  final codes = Int32List(triangles);
  for (var t = 0; t < triangles; t++) {
    codes[t] =
        spread(quantise(centres[t * 3], minX, maxX)) |
        spread(quantise(centres[t * 3 + 1], minY, maxY)) << 1 |
        spread(quantise(centres[t * 3 + 2], minZ, maxZ)) << 2;
  }
  final order = Int32List(triangles);
  for (var t = 0; t < triangles; t++) {
    order[t] = t;
  }
  // Ties by triangle number, so the order is the same on every machine.
  order.sort((a, b) {
    final byCode = codes[a].compareTo(codes[b]);
    return byCode != 0 ? byCode : a.compareTo(b);
  });
  return order;
}

/// Which triangles touch each distinct point of [mesh], matched by position:
/// `(start, triangles, corners)` where the triangles at point `p` are
/// `triangles[start[p]..start[p + 1]]` and `corners[t * 3 + k]` is the point
/// at corner `k` of triangle `t`.
(Int32List, Int32List, Int32List) _trianglesByPoint(MeshData mesh) {
  final stride = mesh.layout.floatsPerVertex;
  final position = mesh.layout.floatOffsetOf(VertexLayout.position.name);
  final vertices = mesh.vertices;
  final pointOf = Int32List(mesh.vertexCount);
  final points = <(double, double, double), int>{};
  for (var v = 0; v < mesh.vertexCount; v++) {
    final o = v * stride + position;
    pointOf[v] = points.putIfAbsent((
      vertices[o],
      vertices[o + 1],
      vertices[o + 2],
    ), () => points.length);
  }

  final indices = mesh.indices;
  final corners = Int32List(indices.length);
  final start = Int32List(points.length + 1);
  for (var i = 0; i < indices.length; i++) {
    corners[i] = pointOf[indices[i]];
    start[corners[i] + 1]++;
  }
  for (var p = 0; p < points.length; p++) {
    start[p + 1] += start[p];
  }
  final fill = Int32List.fromList(start);
  final triangles = Int32List(indices.length);
  for (var i = 0; i < indices.length; i++) {
    triangles[fill[corners[i]]++] = i ~/ 3;
  }
  return (start, triangles, corners);
}
