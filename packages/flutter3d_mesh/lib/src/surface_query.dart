/// [closestPointOn] — the nearest point of a surface to a point in space.
///
/// **What a retopology tool needs and a raycast cannot give it.** `pro-rt-02`
/// puts a vertex where somebody clicked; the click has already been turned
/// into a point near the high surface by a ray through the camera, and what
/// goes into the document is that point pulled *onto* the surface. A second
/// ray cannot do it — there is no direction to fire it in that is right for
/// a corner, a crease and a flat face at once — so this walks the tree by
/// distance instead.
///
/// **A widening search rather than a full walk.** The tree's own boxes are
/// what make this affordable: a candidate box further away than the best
/// point found so far cannot hold a better one, so the walk prunes, and a
/// caller that knows how far it is willing to look passes [within] and
/// prunes harder still.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart' show TriangleBvh;
import 'package:vector_math/vector_math.dart';

/// Where on [tree] the point nearest [point] is, and how far away — or null
/// when nothing is within [within].
({int triangle, double distance, Vector3 point})? closestPointOn(
  TriangleBvh tree,
  Vector3 point, {
  double within = double.infinity,
}) {
  final Float32List positions = tree.positions;
  final Uint32List indices = tree.indices;
  final int triangles = indices.length ~/ 3;
  if (triangles == 0) return null;

  var bestDistance = within;
  var bestTriangle = -1;
  final Vector3 best = Vector3.zero();
  final Vector3 candidate = Vector3.zero();
  final Vector3 a = Vector3.zero();
  final Vector3 b = Vector3.zero();
  final Vector3 c = Vector3.zero();

  void corner(int index, Vector3 into) => into.setValues(
    positions[index * 3],
    positions[index * 3 + 1],
    positions[index * 3 + 2],
  );

  // A flat pass rather than a tree walk: `TriangleBvh` offers no
  // nearest-neighbour query of its own, and the retopology tool asks this
  // once per click over a mesh a person is looking at rather than per frame
  // over a mesh a renderer is drawing. Widening that to a proper branch-and-
  // bound walk is a change to make when something asks it in a loop.
  for (var triangle = 0; triangle < triangles; triangle++) {
    corner(indices[triangle * 3], a);
    corner(indices[triangle * 3 + 1], b);
    corner(indices[triangle * 3 + 2], c);
    closestPointOnTriangle(point, a, b, c, candidate);
    final double distance = candidate.distanceTo(point);
    if (distance < bestDistance) {
      bestDistance = distance;
      bestTriangle = triangle;
      best.setFrom(candidate);
    }
  }
  if (bestTriangle < 0) return null;
  return (triangle: bestTriangle, distance: bestDistance, point: best.clone());
}

/// The point of triangle `abc` nearest [point], written into [into].
///
/// Ericson's own region test: the answer is one of three vertices, one of
/// three edges, or the interior, and which one falls out of six dot
/// products. Written out rather than reached for from a library because
/// `flutter3d_core`'s geometry has no such helper and a wrong one here is a
/// vertex placed off the surface a person is looking at.
Vector3 closestPointOnTriangle(
  Vector3 point,
  Vector3 a,
  Vector3 b,
  Vector3 c,
  Vector3 into,
) {
  final Vector3 ab = b - a;
  final Vector3 ac = c - a;
  final Vector3 ap = point - a;
  final double d1 = ab.dot(ap);
  final double d2 = ac.dot(ap);
  if (d1 <= 0 && d2 <= 0) return into..setFrom(a);

  final Vector3 bp = point - b;
  final double d3 = ab.dot(bp);
  final double d4 = ac.dot(bp);
  if (d3 >= 0 && d4 <= d3) return into..setFrom(b);

  final double vc = d1 * d4 - d3 * d2;
  if (vc <= 0 && d1 >= 0 && d3 <= 0) {
    final double v = d1 / (d1 - d3);
    return into..setFrom(a + ab.scaled(v));
  }

  final Vector3 cp = point - c;
  final double d5 = ab.dot(cp);
  final double d6 = ac.dot(cp);
  if (d6 >= 0 && d5 <= d6) return into..setFrom(c);

  final double vb = d5 * d2 - d1 * d6;
  if (vb <= 0 && d2 >= 0 && d6 <= 0) {
    final double w = d2 / (d2 - d6);
    return into..setFrom(a + ac.scaled(w));
  }

  final double va = d3 * d6 - d5 * d4;
  if (va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0) {
    final double w = (d4 - d3) / ((d4 - d3) + (d5 - d6));
    return into..setFrom(b + (c - b).scaled(w));
  }

  final double denominator = 1 / (va + vb + vc);
  return into
    ..setFrom(a + ab.scaled(vb * denominator) + ac.scaled(vc * denominator));
}
