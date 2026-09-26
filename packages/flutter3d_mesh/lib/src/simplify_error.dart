/// [surfaceDeviation] — how far a simplified mesh really is from the one it
/// was cut from.
///
/// **Measured, not bounded.** `SimplifiedMesh.error` is what the simplifier
/// knows while it runs: the square root of a quadric, the summed squared
/// distances to every plane a merged vertex absorbed. Summed rather than
/// maximised, it reads four to five times what this measures on a sphere cut
/// to a tenth, which is fine for ordering collapses and useless for the question a
/// level of detail asks at run time — is this level less than a pixel away
/// from the full mesh from here? That needs a length in the mesh's own units
/// that is the length, so this measures it after the fact against both
/// surfaces.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
import 'package:vector_math/vector_math.dart';

import 'surface_query.dart';

/// The largest distance between the surfaces of [original] and
/// [simplified], in their shared units — a Hausdorff distance, sampled.
///
/// **Both ways, because each misses what the other catches.** Every vertex
/// of [original] is taken to its nearest point on [simplified], which finds
/// a bump the simplified mesh flattened. Every vertex, edge midpoint and
/// centroid of [simplified] is taken to its nearest point on [original],
/// which finds a large simplified triangle bulging past or sinking under a
/// curve — the sagitta of a chord, on a sphere. The original's own vertices
/// are dense enough to stand for its surface; the simplified mesh's are not,
/// so its triangles are sampled inside as well.
///
/// Zero for two meshes that describe the same surface, and infinite when
/// one of them has triangles and the other none.
double surfaceDeviation(MeshData original, MeshData simplified) {
  final originalTriangles = original.triangleCount;
  final simplifiedTriangles = simplified.triangleCount;
  if (originalTriangles == 0 && simplifiedTriangles == 0) return 0.0;
  if (originalTriangles == 0 || simplifiedTriangles == 0) {
    return double.infinity;
  }

  final originalTree = TriangleBvh.fromMesh(original);
  final simplifiedTree = TriangleBvh.fromMesh(simplified);

  // The original's vertices onto the simplified surface.
  final toSimplified = _NearestSurface(simplifiedTree);
  final originalPositions = originalTree.positions;
  var worst = 0.0;
  for (var i = 0; i < originalPositions.length; i += 3) {
    worst = math.max(
      worst,
      toSimplified.distance(
        originalPositions[i],
        originalPositions[i + 1],
        originalPositions[i + 2],
      ),
    );
  }

  // The simplified triangles, corners and insides, onto the original.
  final toOriginal = _NearestSurface(originalTree);
  final positions = simplifiedTree.positions;
  final indices = simplifiedTree.indices;
  double sample(double x, double y, double z) => toOriginal.distance(x, y, z);
  for (var t = 0; t < indices.length; t += 3) {
    final a = indices[t] * 3;
    final b = indices[t + 1] * 3;
    final c = indices[t + 2] * 3;
    final (ax, ay, az) = (positions[a], positions[a + 1], positions[a + 2]);
    final (bx, by, bz) = (positions[b], positions[b + 1], positions[b + 2]);
    final (cx, cy, cz) = (positions[c], positions[c + 1], positions[c + 2]);
    // Each corner is shared by several triangles and measured by each;
    // measuring it once would need a visited set that costs more than the
    // repeated query on a mesh this size.
    worst = math.max(
      worst,
      <double>[
        sample(ax, ay, az),
        sample((ax + bx) * 0.5, (ay + by) * 0.5, (az + bz) * 0.5),
        sample((bx + cx) * 0.5, (by + cy) * 0.5, (bz + cz) * 0.5),
        sample((cx + ax) * 0.5, (cy + ay) * 0.5, (cz + az) * 0.5),
        sample((ax + bx + cx) / 3, (ay + by + cy) / 3, (az + bz + cz) / 3),
      ].reduce(math.max),
    );
  }
  return worst;
}

/// Nearest-point queries against one tree, by a widening box.
///
/// **A box that doubles until it holds the answer.** `TriangleBvh` answers
/// "which triangles overlap this box" and nothing nearer to a
/// nearest-neighbour question, but that is enough: a triangle within `r` of
/// a point has a point inside the cube of half-side `r` around it, so once
/// the best distance found in the cube is no more than `r` nothing outside
/// it can beat it. The cube starts at the last answer's size, because
/// neighbouring samples are usually about as far off as each other, and a
/// deviation is small against the mesh, so most queries end on the first
/// box.
final class _NearestSurface {
  _NearestSurface(this._tree) : _floor = _floorOf(_tree.positions);

  final TriangleBvh _tree;

  /// The smallest box a query starts from: a millionth of the mesh's
  /// diagonal, so a sample lying on the surface ends on its first box
  /// rather than doubling up from nothing.
  final double _floor;

  /// The half-side the next query starts from.
  late double _reach = _floor;

  final Aabb3 _box = Aabb3();
  final Vector3 _point = Vector3.zero();
  final Vector3 _a = Vector3.zero();
  final Vector3 _b = Vector3.zero();
  final Vector3 _c = Vector3.zero();
  final Vector3 _nearest = Vector3.zero();

  static double _floorOf(Float32List positions) {
    final low = Vector3.all(double.infinity);
    final high = Vector3.all(double.negativeInfinity);
    final point = Vector3.zero();
    for (var i = 0; i < positions.length; i += 3) {
      point.setValues(positions[i], positions[i + 1], positions[i + 2]);
      Vector3.min(low, point, low);
      Vector3.max(high, point, high);
    }
    return math.max((high - low).length * 1e-6, 1e-12);
  }

  /// How far the point `(x, y, z)` is from the nearest triangle.
  ///
  /// Terminates because the tree is never empty here: once the box's
  /// half-side reaches the true distance, the nearest triangle is inside it.
  double distance(double x, double y, double z) {
    _point.setValues(x, y, z);
    final positions = _tree.positions;
    final indices = _tree.indices;
    void corner(int index, Vector3 into) => into.setValues(
      positions[index * 3],
      positions[index * 3 + 1],
      positions[index * 3 + 2],
    );
    for (var reach = _reach; ; reach *= 2.0) {
      _box.min.setValues(x - reach, y - reach, z - reach);
      _box.max.setValues(x + reach, y + reach, z + reach);
      var best = double.infinity;
      _tree.forEachInAabb(_box, (triangle) {
        corner(indices[triangle * 3], _a);
        corner(indices[triangle * 3 + 1], _b);
        corner(indices[triangle * 3 + 2], _c);
        closestPointOnTriangle(_point, _a, _b, _c, _nearest);
        best = math.min(best, _nearest.distanceTo(_point));
      });
      if (best <= reach) {
        // Next time start a little past this one, so a run of similar
        // samples lands inside the first box.
        _reach = math.max(best * 1.5, _floor);
        return best;
      }
    }
  }
}
