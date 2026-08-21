/// Where an agent can stand, baked once from the level's brushes.
///
/// ## Why a grid and not a navigation mesh
///
/// A navmesh earns its complexity by representing *arbitrary* walkable
/// surfaces — slopes, ramps, terrain. This format has none: a `Brush` is a
/// centre and a size, and `level.dart` says so outright — there are no slopes.
/// A navmesh over axis-aligned boxes is a voxelise → region → contour →
/// triangulate pipeline whose output is the rectangles you could have
/// rasterised directly. The most code, the hardest to test, and it buys a
/// representation the format cannot express.
///
/// ## Why it is baked from brushes and not from the collision world
///
/// The collision world contains doors and lifts. Baking from it would freeze
/// whatever position they happened to be in — a closed door would become a
/// permanent wall, and every monster in the level would path around a room it
/// can walk into.
///
/// The brushes are the level's architecture, which is the thing that does not
/// move. A closed door is then something an agent walks *into* and the
/// mechanism deals with, which is what a player does too.
///
/// ## The third dimension, stated rather than guessed
///
/// One height per column. Where a column has more than one surface an agent
/// could stand on, the **lowest** one wins.
///
/// Lowest, not highest, and the reason is the roof: an enclosed room's ceiling
/// brush has open sky above its top face, which makes that face a perfectly
/// good standing surface by every local test there is. Taking the highest span
/// would send every monster in the level onto the roof.
///
/// Where that choice is actually wrong — a walkway over a floor, both of them
/// under a ceiling — the bake says so, through a [LevelIssue] warning, the same
/// way `LevelValidator` reports everything else it cannot decide for you.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../level/level.dart';
import '../level/level_issue.dart';
import '../math/tolerances.dart';

/// A lattice of standing places, and how much room each one has.
final class NavGrid {
  // ignore_for_file: prefer_initializing_formals
  NavGrid._({
    required this.originX,
    required this.originZ,
    required this.cellSize,
    required this.columns,
    required this.rows,
    required this.agentHeight,
    required this.stepHeight,
    required this.maxFall,
    required Float32List floor,
    required Float32List headroom,
    required Uint8List clearance,
  })  : _floor = floor,
        _headroom = headroom,
        _clearance = clearance;

  /// The world position of the corner of cell `(0, 0)`.
  final double originX;
  final double originZ;

  final double cellSize;
  final int columns;
  final int rows;

  /// The shortest agent the bake considered. A cell with less room than this
  /// above its floor is not in the grid at all.
  ///
  /// Taller agents are handled by [headroomAt] rather than by a second bake:
  /// a flow field refuses cells that do not clear its own agent's head.
  final double agentHeight;

  /// How far up a neighbouring cell may be before it is a wall rather than a
  /// step. Matches `CharacterTuning.stepHeight`, and must: a grid that promises
  /// a step the controller will not take sends monsters into walls for ever.
  final double stepHeight;

  /// How far down a neighbouring cell may be before the drop is a cliff.
  final double maxFall;

  final Float32List _floor;
  final Float32List _headroom;
  final Uint8List _clearance;

  int get cellCount => columns * rows;

  /// True when there is nothing to walk on anywhere — an empty level, or one
  /// built entirely from non-solid decoration.
  bool get isEmpty => cellCount == 0;

  int cellIndex(int cx, int cz) => cz * columns + cx;
  int cellX(int index) => index % columns;
  int cellZ(int index) => index ~/ columns;

  /// The cell containing a world point, or `-1` when it is off the grid.
  int cellAtPoint(double x, double z) {
    if (isEmpty) return -1;
    final cx = ((x - originX) / cellSize).floor();
    if (cx < 0 || cx >= columns) return -1;
    final cz = ((z - originZ) / cellSize).floor();
    if (cz < 0 || cz >= rows) return -1;
    return cz * columns + cx;
  }

  int cellAt(Vector3 world) => cellAtPoint(world.x, world.z);

  /// The height of the surface in a cell. Meaningless where [isWalkable] is
  /// false.
  double floorAt(int index) => _floor[index];

  /// Free space above the floor, capped: open sky reports [maxHeadroom] rather
  /// than a number that depends on how tall the level happens to be.
  double headroomAt(int index) => _headroom[index];

  /// How many cells of walkable space surround this one, counting itself.
  ///
  /// One means "walkable, but something is adjacent to it"; three means the
  /// 5×5 block centred here is entirely walkable. Compare against
  /// [clearanceForRadius] to ask whether a body of a given width fits.
  int clearanceAt(int index) => _clearance[index];

  bool isWalkable(int index) => _headroom[index] > 0.0;

  /// The centre of a cell, at its floor height.
  void centreOf(int index, Vector3 out) {
    final cx = index % columns;
    final cz = index ~/ columns;
    out.setValues(
      originX + (cx + 0.5) * cellSize,
      _floor[index],
      originZ + (cz + 0.5) * cellSize,
    );
  }

  /// The [clearanceAt] a body of this radius needs.
  ///
  /// A cell of clearance `k` guarantees a walkable square of half-width
  /// `(k - 0.5) * cellSize` around its centre, so a radius of `r` needs
  /// `k >= r / cellSize + 0.5`. Never less than one, because zero means
  /// "not walkable at all" rather than "narrow".
  int clearanceForRadius(double radius) =>
      math.max(1, (radius / cellSize + 0.5).ceil());

  /// Whether the height difference between two cells is one an agent can take.
  ///
  /// Asymmetric on purpose: you can fall further than you can climb.
  bool canMove(int from, int to) {
    final rise = _floor[to] - _floor[from];
    if (rise > stepHeight) return false;
    if (rise < -maxFall) return false;
    return true;
  }

  /// Open sky, and the largest number [headroomAt] will report.
  static const double maxHeadroom = 8.0;

  /// Rasterises the solid brushes into a lattice of standing places.
  ///
  /// [issues] collects what the bake could not decide — see the library
  /// comment on columns with more than one surface.
  static NavGrid bake(
    Iterable<Brush> brushes, {
    double cellSize = 0.5,
    double agentHeight = 1.7,
    double stepHeight = 0.4,
    double maxFall = 2.0,
    List<LevelIssue>? issues,
  }) {
    final solid = <Brush>[
      for (final brush in brushes)
        if (brush.solid) brush,
    ];
    if (solid.isEmpty) {
      return NavGrid._(
        originX: 0.0,
        originZ: 0.0,
        cellSize: cellSize,
        columns: 0,
        rows: 0,
        agentHeight: agentHeight,
        stepHeight: stepHeight,
        maxFall: maxFall,
        floor: Float32List(0),
        headroom: Float32List(0),
        clearance: Uint8List(0),
      );
    }

    var minX = double.infinity;
    var minZ = double.infinity;
    var maxX = double.negativeInfinity;
    var maxZ = double.negativeInfinity;
    for (final brush in solid) {
      minX = math.min(minX, brush.min.x);
      minZ = math.min(minZ, brush.min.z);
      maxX = math.max(maxX, brush.max.x);
      maxZ = math.max(maxZ, brush.max.z);
    }

    final columns = math.max(1, ((maxX - minX) / cellSize).ceil());
    final rows = math.max(1, ((maxZ - minZ) / cellSize).ceil());
    final count = columns * rows;

    // Which brushes could possibly matter to which cell. Stamped once, so the
    // per-cell work below is proportional to what is actually there rather
    // than to the whole level.
    final buckets = List<List<int>>.generate(count, (_) => <int>[]);
    for (var b = 0; b < solid.length; b++) {
      final brush = solid[b];
      // A boundary hit exactly is a zero-width overlap, which is not one.
      final x0 = _clampInt(
          (((brush.min.x - minX) / cellSize) + Tolerance.gridBias).floor(), 0, columns - 1);
      final x1 = _clampInt(
          (((brush.max.x - minX) / cellSize) - Tolerance.gridBias).floor(), 0, columns - 1);
      final z0 = _clampInt(
          (((brush.min.z - minZ) / cellSize) + Tolerance.gridBias).floor(), 0, rows - 1);
      final z1 = _clampInt(
          (((brush.max.z - minZ) / cellSize) - Tolerance.gridBias).floor(), 0, rows - 1);
      for (var cz = z0; cz <= z1; cz++) {
        final row = cz * columns;
        for (var cx = x0; cx <= x1; cx++) {
          buckets[row + cx].add(b);
        }
      }
    }

    final floor = Float32List(count);
    final headroom = Float32List(count);
    var ambiguous = 0;
    String? firstAmbiguous;
    final tops = <double>[];

    for (var index = 0; index < count; index++) {
      final bucket = buckets[index];
      if (bucket.isEmpty) continue;

      final px = minX + (index % columns + 0.5) * cellSize;
      final pz = minZ + (index ~/ columns + 0.5) * cellSize;

      // The surfaces directly underfoot. A brush that merely clips the corner
      // of this cell is not something you stand on — but it may still be in
      // the way, which is why the headroom pass below looks at the whole
      // bucket. Conservative in the direction that matters: a thin wall
      // crossing a cell blocks it even when no cell centre lands inside it.
      tops.clear();
      for (final b in bucket) {
        final brush = solid[b];
        if (px < brush.min.x || px >= brush.max.x) continue;
        if (pz < brush.min.z || pz >= brush.max.z) continue;
        tops.add(brush.max.y);
      }
      if (tops.isEmpty) continue;
      tops.sort();

      var chosen = -1.0;
      var chosenRoom = 0.0;
      var enclosed = 0;
      var previous = double.negativeInfinity;

      for (final top in tops) {
        if ((top - previous).abs() < Tolerance.sameSurface) continue;
        previous = top;

        var ceiling = top + maxHeadroom;
        var blocked = false;
        for (final b in bucket) {
          final other = solid[b];
          // Entirely at or below the surface, including the brush whose top
          // this is.
          if (other.max.y <= top + Tolerance.sameSurface) continue;
          if (other.min.y <= top + Tolerance.sameSurface) {
            blocked = true;
            break;
          }
          ceiling = math.min(ceiling, other.min.y);
        }
        if (blocked) continue;

        final room = ceiling - top;
        if (room < agentHeight) continue;

        if (room < maxHeadroom) enclosed++;
        if (chosen < 0.0) {
          chosen = top;
          chosenRoom = room;
        }
      }

      if (chosen < 0.0) continue;
      floor[index] = chosen;
      headroom[index] = chosenRoom;

      // Two *enclosed* surfaces is the case a single height cannot express: a
      // walkway over a floor, both under a ceiling. One enclosed surface plus
      // open sky is just a room with a roof, and there is nothing to report.
      if (enclosed >= 2) {
        ambiguous++;
        firstAmbiguous ??= '(${px.toStringAsFixed(2)}, '
            '${pz.toStringAsFixed(2)})';
      }
    }

    if (ambiguous > 0 && issues != null) {
      issues.add(LevelIssue(
        LevelIssueSeverity.warning,
        '$ambiguous navigation ${ambiguous == 1 ? 'column has' : 'columns '
            'have'} more than one enclosed surface; the grid keeps the lowest, '
            'so nothing will path across the upper one. First at '
            '$firstAmbiguous.',
        where: 'navigation',
      ));
    }

    return NavGrid._(
      originX: minX,
      originZ: minZ,
      cellSize: cellSize,
      columns: columns,
      rows: rows,
      agentHeight: agentHeight,
      stepHeight: stepHeight,
      maxFall: maxFall,
      floor: floor,
      headroom: headroom,
      clearance: _clearances(floor, headroom, columns, rows, stepHeight,
          maxFall),
    );
  }

  /// How much room each cell has around it, as a Chebyshev radius in cells.
  ///
  /// Two sweeps rather than a breadth-first search, which is the standard
  /// chamfer transform and gives the exact answer for this metric because the
  /// eight-neighbour distance to any point is reached by a monotone path.
  ///
  /// ## A wall is not only a place with no floor
  ///
  /// The top of a wall is a surface, and by every local test it is a perfectly
  /// good one — it has a floor and open sky above it. Measuring room by
  /// walkability alone therefore counts the wall's own roof as space, and every
  /// corridor in the level comes out two cells wider than it is.
  ///
  /// So a cell next to a floor it cannot reach — three metres up, or a drop it
  /// would not survive — is seeded as though it were next to nothing at all.
  /// That makes the transform measure *reachable* room, which is the thing a
  /// body has to fit into.
  static Uint8List _clearances(
    Float32List floor,
    Float32List headroom,
    int columns,
    int rows,
    double stepHeight,
    double maxFall,
  ) {
    final count = columns * rows;
    final out = Uint8List(count);
    const cap = 255;

    // Cells with an impassable neighbour. Marked first, because the sweeps
    // below propagate from them and a sweep cannot see its own future.
    final edge = Uint8List(count);
    for (var cz = 0; cz < rows; cz++) {
      for (var cx = 0; cx < columns; cx++) {
        final index = cz * columns + cx;
        if (headroom[index] <= 0.0) continue;
        final here = floor[index];
        for (var dz = -1; dz <= 1 && edge[index] == 0; dz++) {
          final nz = cz + dz;
          if (nz < 0 || nz >= rows) {
            edge[index] = 1;
            break;
          }
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dz == 0) continue;
            final nx = cx + dx;
            if (nx < 0 || nx >= columns) {
              edge[index] = 1;
              break;
            }
            final next = nz * columns + nx;
            if (headroom[next] <= 0.0) {
              edge[index] = 1;
              break;
            }
            final rise = floor[next] - here;
            // Impassable in *either* direction: a ledge you can step off but
            // not climb back onto is still an edge to keep away from.
            if (rise > stepHeight ||
                rise < -maxFall ||
                -rise > stepHeight ||
                -rise < -maxFall) {
              edge[index] = 1;
              break;
            }
          }
        }
      }
    }

    for (var cz = 0; cz < rows; cz++) {
      for (var cx = 0; cx < columns; cx++) {
        final index = cz * columns + cx;
        if (headroom[index] <= 0.0) continue;
        if (edge[index] != 0) {
          out[index] = 1;
          continue;
        }
        var best = cap;
        for (var dx = -1; dx <= 1; dx++) {
          best = math.min(best, _read(out, columns, rows, cx + dx, cz - 1));
        }
        best = math.min(best, _read(out, columns, rows, cx - 1, cz));
        out[index] = math.min(cap, best + 1);
      }
    }

    for (var cz = rows - 1; cz >= 0; cz--) {
      for (var cx = columns - 1; cx >= 0; cx--) {
        final index = cz * columns + cx;
        if (headroom[index] <= 0.0 || edge[index] != 0) continue;
        var best = out[index] - 1;
        for (var dx = -1; dx <= 1; dx++) {
          best = math.min(best, _read(out, columns, rows, cx + dx, cz + 1));
        }
        best = math.min(best, _read(out, columns, rows, cx + 1, cz));
        out[index] = math.min(cap, best + 1);
      }
    }

    return out;
  }

  /// Off the grid reads as zero: the level's edge is as solid as a wall, and
  /// an agent whose body hangs over it does not fit.
  static int _read(Uint8List d, int columns, int rows, int cx, int cz) {
    if (cx < 0 || cx >= columns || cz < 0 || cz >= rows) return 0;
    return d[cz * columns + cx];
  }

  static int _clampInt(int value, int low, int high) =>
      value < low ? low : (value > high ? high : value);
}
