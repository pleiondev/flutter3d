/// The jumps a navigation mesh cannot walk: across a gap, up onto a ledge,
/// down off one.
///
/// ## Scanned on the lattice, kept between polygons
///
/// `bakeJumpLinks` scans `NavGrid`'s cells; this scans the bake's own open
/// spans, in whole voxels, so the links are as much a fact about the level
/// as the polygons are. From every floor an agent stands on, in each of
/// eight directions, the scan steps out a column at a time:
///
/// - the same floor, eroded — the strip between where an agent's centre may
///   stand and the floor's real edge — is the run-up and changes nothing;
/// - the same floor where an agent may stand ends the scan: it is walked to,
///   or it is the far side of a corner, and neither is a jump;
/// - nothing within a fall, or a lower floor, is the gap; a lower floor an
///   agent may stand on is a landing;
/// - something solid at the height the body flies through is a ledge it
///   lands on when the reach clears it, and a wall when it does not.
///
/// A link is kept between two polygons, the shortest of those the scan finds
/// between them, since a path search asks "can I get from this polygon to
/// that one" and not from which cell.
///
/// ## What is deliberately not here
///
/// The arc is checked for room only at the height the body took off from:
/// something low in a pit near the landing side of a drop is not seen. No
/// run-up beyond the take-off span, as for the grid's links.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../jump_links.dart';
import 'navmesh_config.dart';
import 'open_field.dart';
import 'span_field.dart';

/// A jump from one polygon to another the walk does not join.
final class NavMeshLink {
  const NavMeshLink({
    required this.from,
    required this.to,
    required this.start,
    required this.end,
    required this.rise,
    required this.gap,
  });

  /// The polygons it leaves and lands on.
  final int from;
  final int to;

  /// Where the body takes off and where it lands, on the floors.
  final Vector3 start;
  final Vector3 end;

  /// The landing's height less the take-off's, in metres. Positive is up.
  final double rise;

  /// The horizontal distance from [start] to [end], in metres.
  final double gap;

  @override
  String toString() =>
      'NavMeshLink($from -> $to, rise ${rise.toStringAsFixed(2)}, '
      'gap ${gap.toStringAsFixed(2)})';
}

/// The eight directions the scan goes, in the order it goes them.
const List<(int, int)> _directions = <(int, int)>[
  (1, 0),
  (-1, 0),
  (0, 1),
  (0, -1),
  (1, 1),
  (1, -1),
  (-1, 1),
  (-1, -1),
];

/// Every jump [reach] makes between floors of [open], as links between the
/// polygons [polygonAt] puts their ends on.
///
/// [solid] is the field [open] was built over, for what stands in the way;
/// [maxFall] is the deepest drop a link lands at the bottom of.
List<NavMeshLink> bakeMeshLinks(
  OpenField open,
  SpanField solid, {
  required NavMeshSettings config,
  required JumpReach reach,
  required double maxFall,
  required int Function(Vector3 at) polygonAt,
}) {
  final links = <NavMeshLink>[];
  if (solid.isEmpty) return links;
  // Which pair each kept link joins. Only looked up, never walked.
  final kept = <(int, int), int>{};

  final columns = open.columns;
  final rows = open.rows;
  final climb = config.walkableClimb;
  final height = config.walkableHeight;
  final maxRise = (reach.maxRise / config.cellHeight).floor();
  final maxDrop = (maxFall / config.cellHeight).floor();
  final longest = reach.gapFor(-maxFall) ?? 0.0;
  final maxCells = (longest / config.cellSize).ceil();

  bool walkable(int span) => open.area[span] != nullArea;

  // Whether anything solid in column [c] reaches into voxels `[low, high)`.
  bool solidIn(int c, int low, int high) =>
      solid.spans[c].any((s) => s.min < high && s.max > low);

  void center(int c, int floor, Vector3 out) => out.setValues(
    solid.originX + (c % columns + 0.5) * config.cellSize,
    solid.originY + floor * config.cellHeight,
    solid.originZ + (c ~/ columns + 0.5) * config.cellSize,
  );

  void link(int s, int c, int t, int tc, double gap) {
    final rise = (open.floor[t] - open.floor[s]) * config.cellHeight;
    if (!reach.takes(rise: rise, gap: gap)) return;
    final start = Vector3.zero();
    final end = Vector3.zero();
    center(c, open.floor[s], start);
    center(tc, open.floor[t], end);
    final from = polygonAt(start);
    final to = polygonAt(end);
    if (from < 0 || to < 0 || from == to) return;
    final made = NavMeshLink(
      from: from,
      to: to,
      start: start,
      end: end,
      rise: rise,
      gap: gap,
    );
    final at = kept[(from, to)];
    if (at == null) {
      kept[(from, to)] = links.length;
      links.add(made);
    } else if (gap < links[at].gap) {
      links[at] = made;
    }
  }

  for (var cz = 0; cz < rows; cz++) {
    for (var cx = 0; cx < columns; cx++) {
      final c = cz * columns + cx;
      for (var s = open.cellStart[c]; s < open.cellStart[c + 1]; s++) {
        if (!walkable(s)) continue;
        final from = open.floor[s];
        for (final (dx, dz) in _directions) {
          final stride = config.cellSize * math.sqrt((dx * dx + dz * dz) * 1.0);
          var crossed = false;
          for (var k = 1; k <= maxCells; k++) {
            final nx = cx + dx * k;
            final nz = cz + dz * k;
            if (nx < 0 || nz < 0 || nx >= columns || nz >= rows) break;
            final n = nz * columns + nx;
            final gap = stride * k;

            // At the height the body flies through: a ledge or a wall.
            if (solidIn(n, from + climb + 1, from + height)) {
              final ledge = _floorIn(open, n, from + climb + 1, from + maxRise);
              if (ledge >= 0) {
                _land(
                  open,
                  nx,
                  nz,
                  dx,
                  dz,
                  k,
                  maxCells,
                  open.floor[ledge],
                  climb,
                  (t, at, j) {
                    link(s, c, t, at, stride * j);
                  },
                );
              }
              break;
            }

            // The highest floor in reach below the body's height.
            var landing = -1;
            for (var t = open.cellStart[n]; t < open.cellStart[n + 1]; t++) {
              final rise = open.floor[t] - from;
              if (rise >= -maxDrop && rise <= climb) landing = t;
            }
            if (landing >= 0 && open.floor[landing] - from >= -climb) {
              // The same floor: run-up while eroded, the end otherwise.
              if (!walkable(landing)) continue;
              if (crossed) link(s, c, landing, n, gap);
              break;
            }
            if (landing >= 0 && walkable(landing)) {
              link(s, c, landing, n, gap);
              break;
            }
            crossed = true;
          }
        }
      }
    }
  }
  return links;
}

/// The highest floor of column [c] from [low] to [high] voxels, or −1.
int _floorIn(OpenField open, int c, int low, int high) {
  for (var t = open.cellStart[c + 1] - 1; t >= open.cellStart[c]; t--) {
    if (open.floor[t] >= low && open.floor[t] <= high) return t;
  }
  return -1;
}

/// Walks on along a ledge whose top is at [level], from step [k] of the
/// scan, to the first span of it — within [climb] of [level] — an agent
/// may stand on, and hands it to
/// [found] with its column and step.
///
/// **The ledge's rim is eroded**, as every floor's edge is: the scan meets
/// it first, and a body that lands there is on a part of the floor where its
/// centre may not stand. It lands, in the scan's terms, a little further in.
void _land(
  OpenField open,
  int cx,
  int cz,
  int dx,
  int dz,
  int k,
  int maxCells,
  int level,
  int climb,
  void Function(int span, int column, int step) found,
) {
  final columns = open.columns;
  for (var j = k; j <= maxCells; j++) {
    final x = cx + dx * (j - k);
    final z = cz + dz * (j - k);
    if (x < 0 || z < 0 || x >= columns || z >= open.rows) return;
    final c = z * columns + x;
    var on = -1;
    for (var t = open.cellStart[c]; t < open.cellStart[c + 1]; t++) {
      if ((open.floor[t] - level).abs() <= climb) on = t;
    }
    if (on < 0) return;
    if (open.area[on] != nullArea) {
      found(on, c, j);
      return;
    }
  }
}
