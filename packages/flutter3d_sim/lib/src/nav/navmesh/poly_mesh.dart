/// Outlines into convex polygons that know their neighbours.
///
/// Each outline is cut into triangles by ear clipping, the triangles are
/// merged back into convex polygons of at most so many corners, and polygons
/// that share an edge are told about each other.
///
/// **All of it on integers.** Corners are lattice points, so every turn test
/// is an exact cross product and no tolerance is involved anywhere: a corner
/// is convex, flat or reflex, and two machines cannot see it differently.
library;

import 'dart:typed_data';

import 'contours.dart';

/// Vertices as lattice `(x, y, z)`; polygons as [maxCorners] vertex indices
/// apiece padded with −1; the neighbour across each edge, or −1; an area per
/// polygon.
typedef PolyMeshParts = ({
  Int32List vertices,
  Int32List polygons,
  Int32List neighbors,
  Uint8List areas,
});

/// Builds the polygon mesh of [contours].
///
/// Every polygon turns left at each corner in the `(x, z)` plane — its signed
/// area there is positive — and none has a reflex corner.
PolyMeshParts buildPolyMesh(List<Contour> contours, {required int maxCorners}) {
  final vertices = <int>[];
  // Lattice column to the vertices already standing in it. Only ever looked
  // up, never walked, so its order is nobody's business.
  final byColumn = <(int, int), List<int>>{};

  // **Corners that differ by a voxel or two are one corner.** Two outlines
  // meeting at a corner each take the highest floor they can see from their
  // own side of it, and at the edge of a step the two can see different
  // floors; welding them is what lets the polygons on each side share it.
  int weld(int x, int y, int z) {
    final column = byColumn.putIfAbsent((x, z), () => <int>[]);
    for (final v in column) {
      if ((vertices[v * 3 + 1] - y).abs() <= 2) return v;
    }
    final v = vertices.length ~/ 3;
    vertices.addAll(<int>[x, y, z]);
    column.add(v);
    return v;
  }

  final polygons = <List<int>>[];
  final areas = <int>[];

  for (final contour in contours) {
    final welded = <int>[];
    for (var i = 0; i < contour.length; i++) {
      final v = weld(
        contour.vertices[i * 3],
        contour.vertices[i * 3 + 1],
        contour.vertices[i * 3 + 2],
      );
      if (welded.isEmpty || welded.last != v) welded.add(v);
    }
    while (welded.length > 1 && welded.first == welded.last) {
      welded.removeLast();
    }
    if (welded.length < 3) continue;

    int px(int v) => vertices[v * 3];
    int pz(int v) => vertices[v * 3 + 2];
    final outline = _signedArea(welded, px, pz) < 0
        ? welded.reversed.toList()
        : welded;

    final pieces = _merge(
      <List<int>>[
        for (final t in _triangulate(outline, px, pz))
          if (_cross(px, pz, t[0], t[1], t[2]) > 0) t,
      ],
      maxCorners,
      px,
      pz,
    );
    polygons.addAll(pieces);
    areas.addAll(List<int>.filled(pieces.length, contour.area));
  }

  final polyArray = Int32List(polygons.length * maxCorners)
    ..fillRange(0, polygons.length * maxCorners, -1);
  for (var p = 0; p < polygons.length; p++) {
    polyArray.setRange(
      p * maxCorners,
      p * maxCorners + polygons[p].length,
      polygons[p],
    );
  }

  return (
    vertices: Int32List.fromList(vertices),
    polygons: polyArray,
    neighbors: _adjacency(polygons, maxCorners),
    areas: Uint8List.fromList(areas),
  );
}

/// Twice the signed area of the polygon in `(x, z)`.
int _signedArea(List<int> poly, int Function(int) px, int Function(int) pz) {
  var sum = 0;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    sum += px(a) * pz(b) - px(b) * pz(a);
  }
  return sum;
}

/// Positive when `a → b → c` turns left in `(x, z)`, zero when it runs
/// straight on.
int _cross(int Function(int) px, int Function(int) pz, int a, int b, int c) =>
    (px(b) - px(a)) * (pz(c) - pz(a)) - (pz(b) - pz(a)) * (px(c) - px(a));

/// Cuts a polygon that turns left into triangles.
///
/// **The shortest diagonal first.** Clipping the ear whose new edge is the
/// shortest keeps slivers out of the triangles, which keeps them out of the
/// polygons merged from them; and since the choice is the first shortest in
/// outline order, it is the same choice every time.
List<List<int>> _triangulate(
  List<int> outline,
  int Function(int) px,
  int Function(int) pz,
) {
  final ring = List<int>.of(outline);
  final triangles = <List<int>>[];

  int cross(int a, int b, int c) => _cross(px, pz, a, b, c);
  bool left(int a, int b, int c) => cross(a, b, c) > 0;
  bool leftOn(int a, int b, int c) => cross(a, b, c) >= 0;
  bool collinear(int a, int b, int c) => cross(a, b, c) == 0;

  bool between(int a, int b, int c) {
    if (!collinear(a, b, c)) return false;
    if (px(a) != px(b)) {
      return (px(a) <= px(c) && px(c) <= px(b)) ||
          (px(a) >= px(c) && px(c) >= px(b));
    }
    return (pz(a) <= pz(c) && pz(c) <= pz(b)) ||
        (pz(a) >= pz(c) && pz(c) >= pz(b));
  }

  bool intersects(int a, int b, int c, int d) {
    final proper =
        !(collinear(a, b, c) ||
            collinear(a, b, d) ||
            collinear(c, d, a) ||
            collinear(c, d, b)) &&
        (left(a, b, c) != left(a, b, d)) &&
        (left(c, d, a) != left(c, d, b));
    return proper ||
        between(a, b, c) ||
        between(a, b, d) ||
        between(c, d, a) ||
        between(c, d, b);
  }

  bool samePlace(int a, int b) => px(a) == px(b) && pz(a) == pz(b);

  // Whether the segment from ring[i] to ring[j] crosses no edge it does not
  // end on.
  bool clearOfEdges(int i, int j) {
    final a = ring[i];
    final b = ring[j];
    for (var k = 0; k < ring.length; k++) {
      final k1 = (k + 1) % ring.length;
      if (k == i || k1 == i || k == j || k1 == j) continue;
      final c = ring[k];
      final d = ring[k1];
      if (samePlace(a, c) ||
          samePlace(b, c) ||
          samePlace(a, d) ||
          samePlace(b, d)) {
        continue;
      }
      if (intersects(a, b, c, d)) return false;
    }
    return true;
  }

  // Whether ring[j] is inside the cone of the corner at ring[i].
  bool inCone(int i, int j) {
    final n = ring.length;
    final here = ring[i];
    final there = ring[j];
    final next = ring[(i + 1) % n];
    final previous = ring[(i + n - 1) % n];
    if (leftOn(previous, here, next)) {
      return left(here, there, previous) && left(there, here, next);
    }
    return !(leftOn(here, there, next) && leftOn(there, here, previous));
  }

  bool diagonal(int i, int j) => inCone(i, j) && clearOfEdges(i, j);

  // ear[i]: the corner after ring[i] can be clipped.
  bool earAfter(int i) => diagonal(i, (i + 2) % ring.length);
  final ear = <bool>[for (var i = 0; i < ring.length; i++) earAfter(i)];

  while (ring.length > 3) {
    final n = ring.length;
    var best = -1;
    var bestLength = 0;
    for (var i = 0; i < n; i++) {
      if (!ear[i]) continue;
      final a = ring[i];
      final c = ring[(i + 2) % n];
      final dx = px(c) - px(a);
      final dz = pz(c) - pz(a);
      final length = dx * dx + dz * dz;
      if (best < 0 || length < bestLength) {
        best = i;
        bestLength = length;
      }
    }
    // No ear: the outline touches itself. Clip the first corner that is not
    // reflex, which loses at worst a sliver, rather than give up on the rest.
    if (best < 0) {
      best = Iterable<int>.generate(n).firstWhere(
        (i) => leftOn(ring[i], ring[(i + 1) % n], ring[(i + 2) % n]),
        orElse: () => -1,
      );
      if (best < 0) return triangles;
    }

    final middle = (best + 1) % n;
    triangles.add(<int>[ring[best], ring[middle], ring[(best + 2) % n]]);
    ring.removeAt(middle);
    ear.removeAt(middle);
    final m = ring.length;
    // The two corners either side of the one clipped have new neighbours, and
    // so does every ear whose diagonal starts at or crosses one of them.
    final before = middle == 0 ? m - 1 : middle - 1;
    for (final k in <int>[(before + m - 1) % m, before, (before + 1) % m]) {
      ear[k] = earAfter(k);
    }
  }
  triangles.add(<int>[ring[0], ring[1], ring[2]]);
  return triangles;
}

/// Merges polygons that share an edge while the result stays convex and
/// within [maxCorners], longest shared edge first.
List<List<int>> _merge(
  List<List<int>> polygons,
  int maxCorners,
  int Function(int) px,
  int Function(int) pz,
) {
  if (maxCorners <= 3) return polygons;
  final polys = List<List<int>>.of(polygons);

  // The shared edge's squared length, with where it sits in each, or null
  // when the two cannot be merged.
  (int, int, int)? value(List<int> a, List<int> b) {
    if (a.length + b.length - 2 > maxCorners) return null;
    for (var i = 0; i < a.length; i++) {
      final a0 = a[i];
      final a1 = a[(i + 1) % a.length];
      for (var j = 0; j < b.length; j++) {
        if (b[j] != a1 || b[(j + 1) % b.length] != a0) continue;
        // Convex at both ends of the seam once it is gone. **Straight on is
        // allowed**: a corner where the neighbour changes along a straight
        // wall has to stay a corner, so both sides of the border have it,
        // and refusing to merge across it cut every such rectangle into
        // three.
        if (_cross(
              px,
              pz,
              a[(i + a.length - 1) % a.length],
              a0,
              b[(j + 2) % b.length],
            ) <
            0) {
          return null;
        }
        if (_cross(
              px,
              pz,
              b[(j + b.length - 1) % b.length],
              a1,
              a[(i + 2) % a.length],
            ) <
            0) {
          return null;
        }
        final dx = px(a1) - px(a0);
        final dz = pz(a1) - pz(a0);
        return (dx * dx + dz * dz, i, j);
      }
    }
    return null;
  }

  while (true) {
    var best = 0;
    var bestA = -1;
    var bestB = -1;
    var edgeA = 0;
    var edgeB = 0;
    for (var p = 0; p < polys.length; p++) {
      for (var q = p + 1; q < polys.length; q++) {
        final v = value(polys[p], polys[q]);
        if (v == null || v.$1 <= best) continue;
        (best, bestA, bestB, edgeA, edgeB) = (v.$1, p, q, v.$2, v.$3);
      }
    }
    if (bestA < 0) return polys;

    final a = polys[bestA];
    final b = polys[bestB];
    polys[bestA] = <int>[
      for (var k = 0; k < a.length - 1; k++) a[(edgeA + 1 + k) % a.length],
      for (var k = 0; k < b.length - 1; k++) b[(edgeB + 1 + k) % b.length],
    ];
    polys[bestB] = polys.last;
    polys.removeLast();
  }
}

/// For each polygon edge, the polygon on the other side of it, or −1.
///
/// Edge `k` of a polygon runs from its corner `k` to corner `k + 1`. Two
/// polygons are neighbours across an edge when they both have it, in opposite
/// directions; the first two to claim an edge keep it.
Int32List _adjacency(List<List<int>> polygons, int maxCorners) {
  final out = Int32List(polygons.length * maxCorners)
    ..fillRange(0, polygons.length * maxCorners, -1);
  final open = <(int, int), int>{};
  for (var p = 0; p < polygons.length; p++) {
    final poly = polygons[p];
    for (var k = 0; k < poly.length; k++) {
      final a = poly[k];
      final b = poly[(k + 1) % poly.length];
      final slot = p * maxCorners + k;
      final other = open.remove((b, a));
      if (other != null) {
        out[slot] = other ~/ maxCorners;
        out[other] = p;
      } else {
        open[(a, b)] = slot;
      }
    }
  }
  return out;
}
