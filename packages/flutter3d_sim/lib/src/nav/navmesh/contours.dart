/// The outline of each region, traced on the lattice and then simplified.
///
/// **Every corner is a lattice point and every comparison is on integers**,
/// apart from the one distance the simplifier measures — and that is a ratio
/// of integers, computed by operations IEEE 754 pins, so it is the same number
/// on every machine.
///
/// ## Why two neighbouring regions agree about their border
///
/// Two regions share an edge in the finished mesh only if both outlines put
/// the same corners along it. So an edge between two regions is never
/// simplified by measuring: only the corners where the neighbour changes are
/// kept on it, and both sides find the same ones. Outer edges are the ones the
/// simplifier measures, and it walks each in one fixed direction whichever
/// region it is tracing, so even those would agree if they were shared.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'open_field.dart';

/// One region's outline: corners as lattice `(x, y, z)`, flattened.
final class Contour {
  Contour(this.region, this.area, this.vertices);

  final int region;
  final int area;
  final Int32List vertices;

  int get length => vertices.length ~/ 3;
}

/// A raw outline corner: where it is, and which region lies beyond the edge
/// that leaves it.
typedef _Corner = ({int x, int y, int z, int beyond, bool areaBorder});

/// Traces every region's outline and simplifies it to within [maxError]
/// cells, in the order the regions are first met in a sweep of the field.
List<Contour> buildContours(
  OpenField field,
  Int32List region, {
  required double maxError,
}) {
  final count = field.spanCount;

  // Which sides of each span face something other than its own region.
  final sides = Uint8List(count);
  for (var s = 0; s < count; s++) {
    if (region[s] == 0) continue;
    sides[s] = <int>[0, 1, 2, 3].fold(0, (bits, dir) {
      final n = field.neighbour(s, dir);
      return n >= 0 && region[n] == region[s] ? bits : bits | (1 << dir);
    });
  }

  final contours = <Contour>[];
  for (var cz = 0; cz < field.rows; cz++) {
    for (var cx = 0; cx < field.columns; cx++) {
      final c = cz * field.columns + cx;
      for (var s = field.cellStart[c]; s < field.cellStart[c + 1]; s++) {
        if (sides[s] == 0 || region[s] == 0) continue;
        final raw = _walk(field, region, sides, cx, cz, s);
        final simple = _removeDegenerate(_simplify(raw, maxError));
        if (simple.length < 3) continue;
        contours.add(
          Contour(
            region[s],
            field.area[s],
            Int32List.fromList(<int>[
              for (final corner in simple) ...<int>[
                corner.x,
                corner.y,
                corner.z,
              ],
            ]),
          ),
        );
      }
    }
  }
  return contours;
}

/// Follows the region's border from span [s], keeping the region on one
/// side, until it is back where it started; clears each side it passes.
List<_Corner> _walk(
  OpenField field,
  Int32List region,
  Uint8List sides,
  int startX,
  int startZ,
  int start,
) {
  final corners = <_Corner>[];
  var x = startX;
  var z = startZ;
  var s = start;
  var dir = 0;
  while ((sides[s] & (1 << dir)) == 0) {
    dir++;
  }
  final startDir = dir;
  final area = field.area[start];

  // Bounded, because a field that broke the invariants this walk relies on
  // must stop rather than hang a bake.
  for (var guard = 0; guard < 4 * field.spanCount + 16; guard++) {
    if ((sides[s] & (1 << dir)) != 0) {
      // The corner at the clockwise end of this side.
      final px = x + (dir == 1 || dir == 2 ? 1 : 0);
      final pz = z + (dir == 0 || dir == 1 ? 1 : 0);
      final n = field.neighbour(s, dir);
      corners.add((
        x: px,
        y: _cornerHeight(field, s, dir),
        z: pz,
        beyond: n >= 0 ? region[n] : 0,
        areaBorder: n >= 0 && field.area[n] != area,
      ));
      sides[s] &= ~(1 << dir);
      dir = (dir + 1) & 3;
    } else {
      final n = field.neighbour(s, dir);
      // A side with no border is a link to the same region by construction.
      if (n < 0) break;
      x += dirX[dir];
      z += dirZ[dir];
      s = n;
      dir = (dir + 3) & 3;
    }
    if (s == start && dir == startDir) break;
  }
  return corners;
}

/// The highest floor among the spans that meet at a corner, so a corner
/// shared by two regions has one height whichever of them is asking.
int _cornerHeight(OpenField field, int s, int dir) {
  final turn = (dir + 1) & 3;
  final a = field.neighbour(s, dir);
  final b = field.neighbour(s, turn);
  final viaA = a < 0 ? -1 : field.neighbour(a, turn);
  final viaB = b < 0 ? -1 : field.neighbour(b, dir);
  return <int>[a, b, viaA, viaB].fold(
    field.floor[s],
    (high, n) => n < 0 ? high : math.max(high, field.floor[n]),
  );
}

/// Keeps the corners where the region beyond changes, then adds back the
/// worst-fitting raw corner of any outer edge until every raw corner is
/// within [maxError] cells of the outline.
List<_Corner> _simplify(List<_Corner> raw, double maxError) {
  final n = raw.length;
  if (n == 0) return raw;
  // Indices into [raw], in outline order.
  final kept = <int>[
    for (var i = 0; i < n; i++)
      if (raw[i].beyond != raw[(i + 1) % n].beyond ||
          raw[i].areaBorder != raw[(i + 1) % n].areaBorder)
        i,
  ];

  if (kept.isEmpty) {
    // An island: start from its lower-left and upper-right corners, which
    // every trace of the same outline finds whatever corner it began at.
    final (lowest, highest) = Iterable<int>.generate(n).fold((0, 0), (pair, i) {
      final c = raw[i];
      final lo = raw[pair.$1];
      final hi = raw[pair.$2];
      return (
        c.x < lo.x || (c.x == lo.x && c.z < lo.z) ? i : pair.$1,
        c.x > hi.x || (c.x == hi.x && c.z > hi.z) ? i : pair.$2,
      );
    });
    kept.addAll(<int>[lowest, highest]);
  }

  final limit = maxError * maxError;
  var i = 0;
  while (i < kept.length) {
    final a = kept[i];
    final b = kept[(i + 1) % kept.length];
    final ra = raw[a];
    final rb = raw[b];
    // Walk the edge from its lexically smaller end, so the same edge measured
    // from either side finds the same worst corner.
    final forward = rb.x > ra.x || (rb.x == ra.x && rb.z > ra.z);
    final from = forward ? ra : rb;
    final to = forward ? rb : ra;
    final step = forward ? 1 : n - 1;
    final end = forward ? b : a;
    var worst = -1;
    var worstDistance = 0.0;
    var k = forward ? (a + step) % n : (b + step) % n;
    // Only an outer edge or an edge between areas is measured; one between
    // two regions keeps the corners both sides agreed on.
    if (raw[k].beyond == 0 || raw[k].areaBorder) {
      while (k != end) {
        final d = _distanceSquared(raw[k], from, to);
        if (d > worstDistance) {
          worstDistance = d;
          worst = k;
        }
        k = (k + step) % n;
      }
    }
    if (worst >= 0 && worstDistance > limit) {
      kept.insert(i + 1, worst);
    } else {
      i++;
    }
  }
  return <_Corner>[for (final k in kept) raw[k]];
}

/// The squared distance in cells from [p] to the segment [a]–[b], in the
/// horizontal plane.
double _distanceSquared(_Corner p, _Corner a, _Corner b) {
  final ux = b.x - a.x;
  final uz = b.z - a.z;
  final px = p.x - a.x;
  final pz = p.z - a.z;
  final length = ux * ux + uz * uz;
  final t = length == 0
      ? 0.0
      : ((ux * px + uz * pz) / length).clamp(0.0, 1.0).toDouble();
  final dx = ux * t - px;
  final dz = uz * t - pz;
  return dx * dx + dz * dz;
}

/// Drops a corner that sits on the next one in plan.
List<_Corner> _removeDegenerate(List<_Corner> corners) {
  final out = <_Corner>[];
  for (var i = 0; i < corners.length; i++) {
    final next = corners[(i + 1) % corners.length];
    if (corners[i].x == next.x &&
        corners[i].z == next.z &&
        corners.length > 1) {
      continue;
    }
    out.add(corners[i]);
  }
  return out;
}
