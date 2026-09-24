import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'vertex_layout.dart';

/// A mesh's index buffer read as consecutive runs of triangles, each with a
/// box and a cone of normals — `C9`, for the scan or the CAD part too big to
/// draw whole every frame.
///
/// **Runs of the buffer rather than lists of triangles.** The clusters tile the
/// indices in order: cluster `i` is `[firstIndex(i), firstIndex(i + 1))`, and
/// the last one ends at the end. The splitter reorders the triangles so that
/// is true, and nothing else about the mesh changes. So a reader that knows
/// nothing of clusters — an older `.f3d` build, the glTF writer, the shadow
/// pass — draws the whole buffer and gets the whole mesh, and the scene pass
/// draws a subset by concatenating runs rather than by gathering triangles.
///
/// **Culled in the mesh's own space.** Whether a triangle faces away from the
/// eye is the sign of a volume, and an affine transform keeps that sign or
/// flips all of them — which the renderer answers by flipping the winding it
/// draws with. So the eye is carried into the mesh instead of every cone out
/// of it, and a node scaled unevenly needs no wider cone.
final class MeshClusters {
  /// Adopts [firstIndices] (one more entry than there are clusters, starting
  /// at zero and ending at the index count) and [data] ([floatsPerCluster]
  /// per cluster, see [measure]).
  MeshClusters({required this.firstIndices, required this.data}) {
    if (firstIndices.isEmpty || firstIndices.first != 0) {
      throw ArgumentError(
        'cluster runs must start at index 0; a run table that skips the '
        'first triangles would leave them out of every culled draw.',
      );
    }
    for (var i = 1; i < firstIndices.length; i++) {
      if (firstIndices[i] <= firstIndices[i - 1] || firstIndices[i] % 3 != 0) {
        throw ArgumentError(
          'cluster ${i - 1} runs from ${firstIndices[i - 1]} to '
          '${firstIndices[i]}: a run is a positive whole number of triangles, '
          'in order.',
        );
      }
    }
    if (data.length != length * floatsPerCluster) {
      throw ArgumentError(
        '${data.length} floats describe $length clusters; each takes '
        '$floatsPerCluster.',
      );
    }
  }

  /// The minimum and maximum corners of the box, the cone's unit axis, and
  /// the cosine and sine of its half-angle.
  static const int floatsPerCluster = 11;

  /// How much wider than the widest normal each cone is made, in radians.
  ///
  /// The cone is compared against an eye carried through a single-precision
  /// inverse of the node's matrix, and a triangle within a fraction of a
  /// degree of edge-on is where float noise decides which way it faces. Half
  /// a degree keeps every culled cluster clear of that, and costs a cluster
  /// only views within half a degree of the edge of where it could be culled.
  static const double coneMargin = 0.01;

  /// Where each run starts in the index buffer, plus where the last one ends.
  final Uint32List firstIndices;

  /// [floatsPerCluster] floats per cluster.
  final Float32List data;

  int get length => firstIndices.length - 1;

  /// The index count the runs tile: the mesh this table belongs to has
  /// exactly this many indices.
  int get indexCount => firstIndices.last;

  int firstIndex(int cluster) => firstIndices[cluster];

  int indexCountOf(int cluster) =>
      firstIndices[cluster + 1] - firstIndices[cluster];

  /// Writes cluster [cluster]'s box, in the mesh's space, into [out].
  void boundsInto(int cluster, Aabb3 out) {
    final o = cluster * floatsPerCluster;
    out.min.setValues(data[o], data[o + 1], data[o + 2]);
    out.max.setValues(data[o + 3], data[o + 4], data[o + 5]);
  }

  /// Whether every triangle of [cluster] faces away from an eye at
  /// ([x], [y], [z]) in the mesh's space.
  ///
  /// True is a promise the rasteriser would cull all of them; anything short
  /// of certain is false. The box is taken as its bounding sphere (centre `c`,
  /// radius `r`) and the normals as the cone (axis `a`, half-angle `θ`), and
  /// with `d = c - eye` every triangle faces away when the angle between `a`
  /// and `d`, plus `θ`, is less than `acos(r / |d|)`: then each normal is
  /// less than that far from `d`, its dot with `d` exceeds `r`, and so its
  /// dot with `p - eye` is positive for every point `p` of the sphere. In
  /// cosines: `r < |d| cos θ` and `a · d > r cos θ + sqrt(|d|² - r²) sin θ`.
  bool facesAwayFrom(int cluster, double x, double y, double z) {
    final o = cluster * floatsPerCluster;
    final cosine = data[o + 9];
    if (!(cosine > 0.0)) return false;
    final sine = data[o + 10];
    final hx = (data[o + 3] - data[o]) * 0.5;
    final hy = (data[o + 4] - data[o + 1]) * 0.5;
    final hz = (data[o + 5] - data[o + 2]) * 0.5;
    final r = math.sqrt(hx * hx + hy * hy + hz * hz);
    final dx = data[o] + hx - x;
    final dy = data[o + 1] + hy - y;
    final dz = data[o + 2] + hz - z;
    final distanceSquared = dx * dx + dy * dy + dz * dz;
    if (!(r * r < distanceSquared * cosine * cosine)) return false;
    final along = data[o + 6] * dx + data[o + 7] * dy + data[o + 8] * dz;
    return along > r * cosine + math.sqrt(distanceSquared - r * r) * sine;
  }

  /// The table for [indices] over the positions in [vertices] (laid out by
  /// [layout]), cut at [firstIndices].
  ///
  /// The cone is the average of the triangles' unit normals, widened to the
  /// one farthest from it plus [coneMargin]. A triangle with no area has no
  /// normal and draws nothing, so it is left out of the cone; a cluster whose
  /// normals spread past a right angle gets a cone that never culls. Normals
  /// are the triangles' own, by winding: the vertex normals say how a surface
  /// is shaded, not which way the rasteriser thinks it faces.
  static MeshClusters measure({
    required VertexLayout layout,
    required Float32List vertices,
    required Uint32List indices,
    required Uint32List firstIndices,
  }) {
    final stride = layout.floatsPerVertex;
    final position = layout.floatOffsetOf(VertexLayout.position.name);
    final count = firstIndices.length - 1;
    final data = Float32List(count * floatsPerCluster);
    // One pass for the axis, one for the widest normal: the angle is only
    // known once the axis is.
    final normals = <double>[];
    for (var cluster = 0; cluster < count; cluster++) {
      var minX = double.infinity, minY = double.infinity;
      var minZ = double.infinity;
      var maxX = -double.infinity, maxY = -double.infinity;
      var maxZ = -double.infinity;
      var sumX = 0.0, sumY = 0.0, sumZ = 0.0;
      normals.clear();
      for (
        var i = firstIndices[cluster];
        i < firstIndices[cluster + 1];
        i += 3
      ) {
        final a = indices[i] * stride + position;
        final b = indices[i + 1] * stride + position;
        final c = indices[i + 2] * stride + position;
        for (var k = 0; k < 3; k++) {
          final v = indices[i + k] * stride + position;
          final px = vertices[v], py = vertices[v + 1], pz = vertices[v + 2];
          if (px < minX) minX = px;
          if (py < minY) minY = py;
          if (pz < minZ) minZ = pz;
          if (px > maxX) maxX = px;
          if (py > maxY) maxY = py;
          if (pz > maxZ) maxZ = pz;
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
        if (length == 0.0) continue;
        normals
          ..add(nx / length)
          ..add(ny / length)
          ..add(nz / length);
        sumX += nx / length;
        sumY += ny / length;
        sumZ += nz / length;
      }

      final o = cluster * floatsPerCluster;
      data
        ..[o] = minX
        ..[o + 1] = minY
        ..[o + 2] = minZ
        ..[o + 3] = maxX
        ..[o + 4] = maxY
        ..[o + 5] = maxZ;

      final sum = math.sqrt(sumX * sumX + sumY * sumY + sumZ * sumZ);
      final (axisX, axisY, axisZ) = sum > 0.0
          ? (sumX / sum, sumY / sum, sumZ / sum)
          : (0.0, 0.0, 1.0);
      var narrowest = 1.0;
      for (var n = 0; n < normals.length; n += 3) {
        final dot =
            normals[n] * axisX +
            normals[n + 1] * axisY +
            normals[n + 2] * axisZ;
        if (dot < narrowest) narrowest = dot;
      }
      final angle = sum > 0.0
          ? math.acos(narrowest.clamp(-1.0, 1.0)) + coneMargin
          : math.pi;
      // Past a right angle the cone holds a normal facing every eye outside
      // the sphere, so it can never cull: cosine nought says so.
      final (cosine, sine) = angle < math.pi / 2
          ? (math.cos(angle), math.sin(angle))
          : (0.0, 1.0);
      // Stored in single precision, rounded the safe way: a cosine a hair
      // larger or a sine a hair smaller would narrow the cone.
      data
        ..[o + 6] = axisX
        ..[o + 7] = axisY
        ..[o + 8] = axisZ
        ..[o + 9] = _below(cosine)
        ..[o + 10] = _above(sine);
    }
    return MeshClusters(firstIndices: firstIndices, data: data);
  }

  static final Float32List _round = Float32List(1);

  /// The largest single-precision value at or below [value].
  static double _below(double value) {
    _round[0] = value;
    final stored = _round[0];
    if (stored <= value) return stored;
    _round[0] = stored - stored.abs() * 1.2e-7 - 1e-38;
    return _round[0];
  }

  /// The smallest single-precision value at or above [value].
  static double _above(double value) {
    _round[0] = value;
    final stored = _round[0];
    if (stored >= value) return stored;
    _round[0] = stored + stored.abs() * 1.2e-7 + 1e-38;
    return _round[0];
  }

  @override
  String toString() => 'MeshClusters($length clusters, $indexCount indices)';
}
