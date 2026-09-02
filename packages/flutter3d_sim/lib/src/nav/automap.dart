import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'nav_grid.dart';

/// The level as the player has seen it, from above.
///
/// **A brush level already has its map: the navigation grid.** Every cell an
/// agent can stand in is a cell of floor, every cell it cannot step into from
/// one it can is a wall, and the grid was baked from the brushes for the
/// monsters before anybody thought of drawing it. What this adds is memory —
/// which of those cells the player has been near — and that is the whole of
/// an automap: floor where they walked, walls where the floor stopped, nothing
/// where they have not been.
///
/// ## Revealing walks, it does not radiate
///
/// A circle of six metres around the player would show the room on the other
/// side of the wall, which is the one thing a map must not do before the door
/// is opened. So the reveal is a flood over the grid: from the player's cell
/// outward across cells an agent could step between, stopping at the radius.
/// A wall stops the flood the way it stops the player, and a doorway lets it
/// through the way it lets the player through. The cells the flood reaches
/// are floor; the cells around them it could not step into are the walls
/// drawn around it.
///
/// **Walls are the cells the walk could not enter, not the cells nobody can
/// stand in.** The grid calls the roof walkable — a wall's column has one
/// standing place, the top of the ceiling under open sky — so "unwalkable"
/// would miss every wall of every room with a ceiling. What makes a wall a
/// wall is that the step up to it is one the player cannot take, which is
/// what `NavGrid.canMove` already decides for the monsters.
///
/// Run once per cell the player enters rather than once per step: a flood of
/// a six-metre radius over quarter-metre cells is a few hundred cells, and a
/// player standing still crosses none.
///
/// ## In the snapshot
///
/// What has been seen is part of the run — a save that forgot the map would
/// hand the player back a level they had explored and a map that said they
/// had not — so it is written into the snapshot and read back. As runs of
/// bits rather than the bits: the crypt's grid is twenty-five thousand cells
/// and its bitset four kilobytes however little was seen, where the runs of
/// a partly explored level are a few hundred bytes. Deterministic like
/// everything in a step: the flood's order is the grid's order, so a replay
/// reveals what the run revealed.
final class Automap {
  Automap(this.grid, {this.revealRadius = 6.0})
    : assert(revealRadius > 0.0),
      _floor = Uint8List((grid.cellCount + 7) >> 3),
      _wall = Uint8List((grid.cellCount + 7) >> 3);

  final NavGrid grid;

  /// How far the flood reaches from the player, in metres along the walk.
  final double revealRadius;

  /// Cells the walk reached: floor.
  final Uint8List _floor;

  /// Cells beside the floor the walk could not enter: walls.
  final Uint8List _wall;

  int _lastCell = -1;
  bool _all = false;

  static bool _bit(Uint8List bits, int index) =>
      (bits[index >> 3] & (1 << (index & 7))) != 0;

  static void _set(Uint8List bits, int index) {
    bits[index >> 3] |= 1 << (index & 7);
  }

  /// Whether cell [index] is on the map at all, as floor or as wall.
  bool isRevealed(int index) => _bit(_floor, index) || _bit(_wall, index);

  /// Whether cell [index] is floor the player has been near.
  bool isFloor(int index) => _bit(_floor, index);

  /// Whether cell [index] is a wall: beside seen floor, and not to be stepped
  /// into from it. What the map draws dark around what it draws light.
  bool isWall(int index) => _bit(_wall, index) && !_bit(_floor, index);

  /// How many cells are on the map.
  int get revealedCount =>
      Iterable<int>.generate(grid.cellCount).where(isRevealed).length;

  /// Whether a map pickup has shown the whole level.
  bool get everythingRevealed => _all;

  /// Reveals what a player standing at [at] can have seen.
  ///
  /// Does nothing when the player is still in the cell they were in at the
  /// last call, off the grid, or in a cell that is not floor — a player mid-
  /// jump over a pit sees from where they took off, which was revealed then.
  void reveal(Vector3 at) {
    if (_all || grid.isEmpty) return;
    final start = grid.cellAt(at);
    if (start < 0 || start == _lastCell) return;
    _lastCell = start;
    if (!grid.isWalkable(start)) return;
    _flood(start, revealRadius);
  }

  /// Shows everything a player standing at [at] could ever walk to, the way
  /// a map pickup does.
  ///
  /// From where they stand rather than every standing place in the grid,
  /// because the grid's standing places include the roof.
  void revealAll(Vector3 at) {
    final start = grid.cellAt(at);
    if (start < 0 || !grid.isWalkable(start)) return;
    _all = true;
    _flood(start, double.infinity);
  }

  final List<int> _queue = <int>[];
  Float32List _distance = Float32List(0);

  /// Breadth-first over cells the player could step between from [start],
  /// up to [radius] metres of walked distance. Every cell reached is floor;
  /// every neighbour it could not step into is wall.
  void _flood(int start, double radius) {
    final cells = grid.cellCount;
    if (_distance.length != cells) _distance = Float32List(cells);
    _distance.fillRange(0, cells, double.infinity);
    _queue
      ..clear()
      ..add(start);
    _distance[start] = 0.0;
    final columns = grid.columns;
    final rows = grid.rows;
    final step = grid.cellSize;
    var head = 0;
    while (head < _queue.length) {
      final cell = _queue[head++];
      _set(_floor, cell);
      final here = _distance[cell];
      final cx = grid.cellX(cell);
      final cz = grid.cellZ(cell);
      for (var dz = -1; dz <= 1; dz++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dz == 0) continue;
          final nx = cx + dx;
          final nz = cz + dz;
          if (nx < 0 || nx >= columns || nz < 0 || nz >= rows) continue;
          final next = grid.cellIndex(nx, nz);
          final enterable = grid.isWalkable(next) && grid.canMove(cell, next);
          if (!enterable) {
            _set(_wall, next);
            continue;
          }
          // The walk itself is four-connected; the diagonals only decide
          // what is a wall, so a corner is drawn as one.
          if (dx != 0 && dz != 0) continue;
          final there = here + step;
          if (there > radius || there >= _distance[next]) continue;
          _distance[next] = there;
          _queue.add(next);
        }
      }
    }
  }

  Map<String, Object?> save() => <String, Object?>{
    'floor': _runs(_floor, grid.cellCount),
    'wall': _runs(_wall, grid.cellCount),
    'all': _all,
  };

  /// Reads what was seen. Runs that do not add up to this grid's cells —
  /// another level's, another cell size's — are ignored rather than applied
  /// over the wrong cells.
  void restore(Map<String, Object?> from) {
    _lastCell = -1;
    final all = from['all'];
    _all = all is bool && all;
    _floor.fillRange(0, _floor.length, 0);
    _wall.fillRange(0, _wall.length, 0);
    _unruns(from['floor'], _floor, grid.cellCount);
    _unruns(from['wall'], _wall, grid.cellCount);
  }

  /// A bitset as the lengths of its runs, starting with a run of zeros.
  static List<int> _runs(Uint8List bits, int count) {
    final runs = <int>[];
    var current = false;
    var length = 0;
    for (var i = 0; i < count; i++) {
      final bit = _bit(bits, i);
      if (bit == current) {
        length++;
      } else {
        runs.add(length);
        current = bit;
        length = 1;
      }
    }
    runs.add(length);
    return runs;
  }

  static void _unruns(Object? encoded, Uint8List into, int count) {
    if (encoded is! List<Object?>) return;
    var total = 0;
    for (final run in encoded) {
      if (run is! num) return;
      total += run.toInt();
    }
    if (total != count) return;
    var index = 0;
    var current = false;
    for (final run in encoded) {
      final length = (run! as num).toInt();
      if (current) {
        for (var i = index; i < index + length; i++) {
          _set(into, i);
        }
      }
      index += length;
      current = !current;
    }
  }
}
