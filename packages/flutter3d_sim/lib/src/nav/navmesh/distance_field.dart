/// How far each floor is from the nearest place an agent cannot go, and the
/// two filters that read it.
///
/// **The metric is `NavGrid`'s on purpose.** A span is at distance one when
/// any of its eight neighbours is missing or a step too far; the rest is a
/// Chebyshev distance by the two-sweep chamfer `NavGrid._clearances` uses.
/// The mesh then keeps exactly the floors whose clearance a flow field for a
/// body of the same radius would accept, and the two navigations of one level
/// disagree about nothing but shape.
library;

import 'dart:typed_data';

import 'open_field.dart';
import 'span_field.dart';

/// The clearance of every span, in cells; zero for a refused span.
Uint16List distanceField(OpenField field, int climb) {
  final count = field.spanCount;
  const cap = 0xffff;
  final dist = Uint16List(count);

  // The diagonal from [s] between [dir] and the next direction round, reached
  // along either side of the corner, or −1.
  int diagonal(int s, int dir) {
    final turn = (dir + 1) & 3;
    final a = field.neighbour(s, dir);
    final viaA = a < 0 ? -1 : field.neighbour(a, turn);
    if (viaA >= 0) return viaA;
    final b = field.neighbour(s, turn);
    return b < 0 ? -1 : field.neighbour(b, dir);
  }

  bool atEdge(int s) {
    for (var dir = 0; dir < 4; dir++) {
      if (field.neighbour(s, dir) < 0) return true;
      final d = diagonal(s, dir);
      if (d < 0 || (field.floor[d] - field.floor[s]).abs() > climb) return true;
    }
    return false;
  }

  for (var s = 0; s < count; s++) {
    if (field.area[s] == nullArea) continue;
    dist[s] = atEdge(s) ? 1 : cap;
  }

  // The read of a neighbour's distance through a path of directions; an edge
  // span is never relaxed, so an interior one always has all eight.
  int through(int s, int first, [int? second]) {
    final a = field.neighbour(s, first);
    if (a < 0) return 0;
    if (second == null) return dist[a];
    final b = field.neighbour(a, second);
    return b < 0 ? 0 : dist[b];
  }

  int relaxed(int s, List<int> candidates) =>
      candidates.fold(dist[s] - 1, (best, d) => d < best ? d : best) + 1;

  for (var cz = 0; cz < field.rows; cz++) {
    for (var cx = 0; cx < field.columns; cx++) {
      final c = cz * field.columns + cx;
      for (var s = field.cellStart[c]; s < field.cellStart[c + 1]; s++) {
        if (dist[s] <= 1) continue;
        dist[s] = relaxed(s, <int>[
          through(s, 0),
          through(s, 0, 3),
          through(s, 3),
          through(s, 3, 2),
        ]);
      }
    }
  }
  for (var cz = field.rows - 1; cz >= 0; cz--) {
    for (var cx = field.columns - 1; cx >= 0; cx--) {
      final c = cz * field.columns + cx;
      for (var s = field.cellStart[c + 1] - 1; s >= field.cellStart[c]; s--) {
        if (dist[s] <= 1) continue;
        dist[s] = relaxed(s, <int>[
          through(s, 2),
          through(s, 2, 1),
          through(s, 1),
          through(s, 1, 0),
        ]);
      }
    }
  }
  return dist;
}

/// Refuses every span closer to an edge than [need] cells.
///
/// All at once, from one distance field, rather than peeling a ring at a
/// time: a ring peeled first would change what the next ring measures from.
void erode(OpenField field, Uint16List dist, int need) {
  for (var s = 0; s < field.spanCount; s++) {
    if (dist[s] < need) field.area[s] = nullArea;
  }
}

/// Refuses every connected island of fewer than [minCells] spans.
///
/// Flooded from the lowest-numbered span of each island, neighbours in
/// direction order, so the islands and what survives of them are the same on
/// every run.
void dropIslands(OpenField field, int minCells) {
  if (minCells <= 1) return;
  final seen = Uint8List(field.spanCount);
  final island = <int>[];
  for (var start = 0; start < field.spanCount; start++) {
    if (seen[start] != 0 || field.area[start] == nullArea) continue;
    island
      ..clear()
      ..add(start);
    seen[start] = 1;
    for (var k = 0; k < island.length; k++) {
      for (var dir = 0; dir < 4; dir++) {
        final n = field.neighbour(island[k], dir);
        if (n < 0 || seen[n] != 0) continue;
        seen[n] = 1;
        island.add(n);
      }
    }
    if (island.length < minCells) {
      for (final s in island) {
        field.area[s] = nullArea;
      }
    }
  }
}
