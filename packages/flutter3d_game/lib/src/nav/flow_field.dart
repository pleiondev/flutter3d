/// One sweep of Dijkstra from where the player is, read by everything that
/// wants to get there.
///
/// ## Why not A\* per monster
///
/// Because `monster_system.dart` already wrote down the fact that decides it:
/// *"Nothing targets anything but the player."* With one goal, thirty A\*
/// searches compute thirty prefixes of the same tree. One sweep outward from
/// the goal gives every agent in the level its direction as an array lookup,
/// and the sweep only has to run again when the player crosses into a
/// different cell.
///
/// The sweep runs *from* the goal, so the stored direction points along the
/// descent — the parent link, recorded while relaxing. Nothing has to be
/// gradient-sampled afterwards, and a cell that was never reached keeps a zero
/// direction, which is how "there is no way there from here" is reported.
///
/// ## One field per class of body
///
/// A field refuses cells its agent does not fit in, both across
/// ([NavGrid.clearanceAt]) and up ([NavGrid.headroomAt]). A single shared field
/// would have to pick one body: too wide and it walls the small monsters out of
/// corridors they fit in, too narrow and it marches the big ones into gaps they
/// do not. [Navigation] keeps one field per class and builds them on demand,
/// which is usually two or three for a whole game.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cell_heap.dart';
import 'nav_grid.dart';

/// The distance to the goal from everywhere, and which way is downhill.
final class FlowField {
  FlowField(this.grid, {this.minClearance = 1, this.minHeadroom = 0.0})
    : _cost = Int32List(grid.cellCount),
      _dx = Int8List(grid.cellCount),
      _dz = Int8List(grid.cellCount) {
    // A fresh `Int32List` is zeros, and zero is a real cost meaning "you are
    // standing on the goal". Before the first sweep nothing is reachable.
    _cost.fillRange(0, _cost.length, unreachable);
  }

  final NavGrid grid;

  /// How wide the body is, in cells. See [NavGrid.clearanceForRadius].
  final int minClearance;

  /// How tall the body is. Zero accepts anything the grid baked.
  final double minHeadroom;

  final Int32List _cost;
  final Int8List _dx;
  final Int8List _dz;

  /// Integer costs, because a Dijkstra over floats accumulates a different
  /// total along paths of equal length and then picks between them by rounding
  /// error. 10 and 14 are the usual pair: 14/10 is within half a percent of √2.
  static const int _straight = 10;
  static const int _diagonal = 14;
  static const int unreachable = 1 << 29;

  /// The cell the field currently flows towards, or `-1` when the last goal
  /// was somewhere no body of this class can be.
  int get goalCell => _goalCell;
  int _goalCell = -1;

  final Vector3 _centre = Vector3.zero();
  final CellHeap _heap = CellHeap();

  bool fits(int index) =>
      grid.isWalkable(index) &&
      grid.clearanceAt(index) >= minClearance &&
      grid.headroomAt(index) >= minHeadroom;

  /// Cost to the goal in tenths of a cell, or [unreachable].
  int costAt(int index) => _cost[index];

  /// How far it is to the goal by walking, in world units, or `null` when
  /// there is no way at all.
  ///
  /// Recorded because it is free: a walking-distance field is what "everything
  /// within twenty metres of the noise wakes up" needs, and the sweep has
  /// already computed it.
  double? walkingDistanceTo(Vector3 world) {
    final cell = grid.cellAt(world);
    if (cell < 0) return null;
    final cost = _cost[cell];
    if (cost >= unreachable) return null;
    return cost * grid.cellSize / _straight;
  }

  /// Re-sweeps towards [goal]. Cheap to call every step: it returns without
  /// doing anything while the goal stays in the same cell.
  void update(Vector3 goal) {
    final cell = _resolveGoal(goal);
    if (cell == _goalCell) return;
    rebuild(goal);
  }

  /// Re-sweeps unconditionally. Call this when the level itself changed.
  void rebuild(Vector3 goal) {
    _cost.fillRange(0, _cost.length, unreachable);
    _dx.fillRange(0, _dx.length, 0);
    _dz.fillRange(0, _dz.length, 0);
    _goalCell = _resolveGoal(goal);
    if (_goalCell < 0) return;

    final columns = grid.columns;
    final rows = grid.rows;
    _cost[_goalCell] = 0;
    _heap
      ..clear()
      ..push(_goalCell, 0);

    while (!_heap.isEmpty) {
      final cell = _heap.pop();
      final cost = _heap.poppedCost;
      if (cost > _cost[cell]) continue;

      final cx = cell % columns;
      final cz = cell ~/ columns;

      for (var dz = -1; dz <= 1; dz++) {
        final nz = cz + dz;
        if (nz < 0 || nz >= rows) continue;
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dz == 0) continue;
          final nx = cx + dx;
          if (nx < 0 || nx >= columns) continue;

          final next = nz * columns + nx;
          if (!fits(next)) continue;
          // The sweep runs outward from the goal, but the agent will walk the
          // other way — so the height rule is asked in the direction of
          // travel. Climbing up to a ledge and dropping off it are different
          // limits, and asking backwards would let a monster path up a cliff.
          if (!grid.canMove(next, cell)) continue;

          var cost2 = cost + _straight;
          if (dx != 0 && dz != 0) {
            // A diagonal needs both of its sides open, or an agent cuts the
            // corner of a wall and grinds along it — which is precisely the
            // behaviour this whole file exists to remove.
            final sideA = nz * columns + cx;
            final sideB = cz * columns + nx;
            if (!fits(sideA) || !fits(sideB)) continue;
            if (!grid.canMove(sideA, cell) || !grid.canMove(sideB, cell)) {
              continue;
            }
            cost2 = cost + _diagonal;
          }

          if (cost2 >= _cost[next]) continue;
          _cost[next] = cost2;
          // Towards the cell it was reached from: that is downhill.
          _dx[next] = -dx;
          _dz[next] = -dz;
          _heap.push(next, cost2);
        }
      }
    }
  }

  /// The direction to walk from [from], written into [out] as a horizontal
  /// unit vector.
  ///
  /// False when there is nothing to say — off the grid, no route to the goal,
  /// or already in the goal's own cell. A caller that gets false should walk
  /// straight at its target: within one cell that *is* the right answer, and
  /// steering by the field there would have an agent circling a cell centre
  /// half a metre from the player.
  bool descend(Vector3 from, Vector3 out) {
    if (_goalCell < 0) return false;
    final cell = grid.cellAt(from);
    if (cell < 0) return false;
    if (cell == _goalCell) return false;
    if (_cost[cell] >= unreachable) return false;

    final dx = _dx[cell];
    final dz = _dz[cell];
    // **Belt and braces, and it is worth saying so.** A cell cheaper than
    // `unreachable` was relaxed, and relaxing records a direction — so the only
    // cell with a cost and no direction is the goal's own, which the line above
    // has already sent away. Mutating this to `return true` breaks no test,
    // because there is no way to reach it. It stays because the alternative,
    // if the sweep ever does leave such a cell, is an agent walking along
    // whatever the previous caller left in `out`.
    if (dx == 0 && dz == 0) return false;

    final next = (grid.cellZ(cell) + dz) * grid.columns + grid.cellX(cell) + dx;
    grid.centreOf(next, _centre);
    // Towards the next cell's centre rather than along the raw eight-way
    // offset: an agent that walks the offsets moves in staircases, and one
    // that aims at centres moves in a line whenever the cells are in one.
    out.setValues(_centre.x - from.x, 0.0, _centre.z - from.z);
    if (out.length2 < 1e-8) return false;
    out.normalize();
    return true;
  }

  /// The goal's own cell, or the nearest one a body of this class fits in.
  ///
  /// The search matters: the player standing in a doorway a tank cannot enter
  /// would otherwise make every tank in the level stop, when what they should
  /// do is come as close as they fit and wait there.
  int _resolveGoal(Vector3 goal) {
    final direct = grid.cellAt(goal);
    if (direct >= 0 && fits(direct)) return direct;
    if (grid.isEmpty) return -1;

    final gx = ((goal.x - grid.originX) / grid.cellSize).floor();
    final gz = ((goal.z - grid.originZ) / grid.cellSize).floor();
    for (var ring = 1; ring <= 6; ring++) {
      var best = -1;
      var bestDistance = 0;
      for (var dz = -ring; dz <= ring; dz++) {
        for (var dx = -ring; dx <= ring; dx++) {
          if (dx.abs() != ring && dz.abs() != ring) continue;
          final nx = gx + dx;
          final nz = gz + dz;
          if (nx < 0 || nx >= grid.columns || nz < 0 || nz >= grid.rows) {
            continue;
          }
          final index = nz * grid.columns + nx;
          if (!fits(index)) continue;
          final d = dx * dx + dz * dz;
          if (best < 0 || d < bestDistance) {
            best = index;
            bestDistance = d;
          }
        }
      }
      if (best >= 0) return best;
    }
    return -1;
  }
}
