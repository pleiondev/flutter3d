/// What each side knows about the map, and what it can see of it right now.
///
/// **Two states, not one, and the second is the interesting one.** A cell is
/// *explored* once anybody of that side has been near it, for ever; it is
/// *visible* only while somebody is near it now. Collapsing the pair into "can
/// see" would throw away the whole of what a strategy's map memory is: the
/// player who found a seam an hour ago should still know where it is, and
/// should not know whether it has been emptied since. That second half comes
/// out of the split for free — a worker sent to a remembered seam that somebody
/// else has drained walks there, finds nothing and is given something else to
/// do, which is exactly right and needed no code.
///
/// **Sight is a radius, not a line of sight.** A ridge does not block it. That
/// is a decision rather than an omission: line of sight over a heightfield
/// means marching a ray per cell per source, which is the one thing in this
/// genre that scales with both the crowd and the map, and nothing here has
/// asked for it. The day something does, it goes behind this same interface and
/// nothing above changes.
///
/// **Its own lattice, coarser than the navigation grid.** Four metres against
/// two: fog is looked at rather than walked on, and the cost of revealing a
/// disc goes as the square of how fine the cells are. Marking a twenty-metre
/// circle touches about eighty cells at four metres and three hundred at two,
/// for a difference a camera above the map cannot see.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// What the sides know, cell by cell.
final class FogOfWar {
  /// Covers [ground] with [cellSize]-metre cells, for [sides] sides.
  FogOfWar({required this.ground, this.cellSize = 4.0, this.sides = 2})
    : assert(cellSize > 0.0, 'a lattice of no size covers nothing'),
      assert(sides > 0, 'a map nobody looks at'),
      originX = ground.origin.x,
      originZ = ground.origin.z,
      columns = (ground.width / cellSize).ceil() + 1,
      rows = (ground.depth / cellSize).ceil() + 1 {
    _state = Uint8List(sides * columns * rows);
  }

  /// The ground the lattice covers.
  ///
  /// Kept because the drawing half needs it: a fog tile has to sit above the
  /// hill it hides, and the only thing that knows how high that is, is this.
  final Heightfield ground;

  /// How wide a cell is, in metres.
  final double cellSize;

  /// How many sides have a view of their own.
  final int sides;

  /// The corner the lattice starts at.
  final double originX;
  final double originZ;

  /// How many cells across and down.
  final int columns;
  final int rows;

  /// One byte a cell a side: bit one is explored, bit two is visible.
  ///
  /// A byte rather than two bits packed, because the packing saves a lattice
  /// measured in kilobytes and costs a shift and a mask on the hottest read
  /// this file has — the one the drawing half makes once per cell per frame.
  late final Uint8List _state;

  static const int _explored = 1;
  static const int _visible = 2;

  /// How many cells the lattice has.
  int get cellCount => columns * rows;

  /// The cell a world point falls in, or `-1` for a point off the lattice.
  int cellAt(double x, double z) {
    final int cx = ((x - originX) / cellSize).floor();
    if (cx < 0 || cx >= columns) return -1;
    final int cz = ((z - originZ) / cellSize).floor();
    if (cz < 0 || cz >= rows) return -1;
    return cz * columns + cx;
  }

  /// Where a cell's middle is, along X and Z.
  double centreX(int cell) => originX + (cell % columns + 0.5) * cellSize;
  double centreZ(int cell) => originZ + (cell ~/ columns + 0.5) * cellSize;

  /// Whether [side] can see [cell] at this moment.
  bool isVisible(int side, int cell) =>
      _state[side * cellCount + cell] & _visible != 0;

  /// Whether [side] has ever seen [cell].
  bool isExplored(int side, int cell) =>
      _state[side * cellCount + cell] & _explored != 0;

  /// Whether [side] can see a world point now. False off the lattice.
  bool sees(int side, double x, double z) {
    final int cell = cellAt(x, z);
    return cell >= 0 && isVisible(side, cell);
  }

  /// Whether [side] has ever seen a world point. False off the lattice.
  bool knows(int side, double x, double z) {
    final int cell = cellAt(x, z);
    return cell >= 0 && isExplored(side, cell);
  }

  /// Forgets what every side can see now, keeping what they have explored.
  ///
  /// Called before the sources are walked, because visibility is recomputed
  /// from scratch rather than tracked: a unit that moved would otherwise have
  /// to un-see the cells it left, and working out which those are is the same
  /// work as marking the ones it is in now, done twice and wrong once.
  void forgetVisible() {
    for (var i = 0; i < _state.length; i++) {
      _state[i] &= ~_visible;
    }
  }

  /// Marks everything within [radius] of a point as seen by [side], now.
  void reveal(int side, double x, double z, double radius) {
    final int minX = (((x - radius) - originX) / cellSize).floor();
    final int maxX = (((x + radius) - originX) / cellSize).floor();
    final int minZ = (((z - radius) - originZ) / cellSize).floor();
    final int maxZ = (((z + radius) - originZ) / cellSize).floor();
    final double reach = radius * radius;
    final int base = side * cellCount;

    for (var cz = minZ < 0 ? 0 : minZ; cz <= maxZ && cz < rows; cz++) {
      final double dz = originZ + (cz + 0.5) * cellSize - z;
      for (var cx = minX < 0 ? 0 : minX; cx <= maxX && cx < columns; cx++) {
        final double dx = originX + (cx + 0.5) * cellSize - x;
        // A disc rather than the square the bounds are: a square reveal reads
        // as a crowd walking around inside a lit box, and the corners of that
        // box are half again as far as the sight it was given.
        if (dx * dx + dz * dz > reach) continue;
        _state[base + cz * columns + cx] |= _explored | _visible;
      }
    }
  }

  /// The unexplored cell nearest to a point, or `-1` when there is nowhere left
  /// worth going.
  ///
  /// For a policy that has run out of known work and has to go and look. Walked
  /// in index order so that ties break the same way on every run; the map is a
  /// few thousand cells, and a scan of it is cheaper than the bookkeeping that
  /// would avoid the scan.
  ///
  /// **[reachable] is not optional in practice, and the reason took a test to
  /// find.** A lattice has to have a cell for the far edge of the map, so its
  /// last row and column hang over the edge; their middles are off the ground
  /// entirely. A scout sent to one of those is sent nowhere — the step finds no
  /// cell under the goal, gives no direction, and the unit stands still holding
  /// an order it can never carry out while the seam it was going to find stays
  /// dark for the rest of the match. Passing the walkability test makes the
  /// frontier mean *ground a scout could stand on*, which is what it was always
  /// supposed to mean.
  int nearestUnexplored(
    int side,
    double x,
    double z, {
    bool Function(double x, double z)? reachable,
  }) {
    var best = -1;
    var bestAt = double.infinity;
    final int base = side * cellCount;
    for (var cell = 0; cell < cellCount; cell++) {
      if (_state[base + cell] & _explored != 0) continue;
      final double cellX = centreX(cell);
      final double cellZ = centreZ(cell);
      final double dx = cellX - x;
      final double dz = cellZ - z;
      final double at = dx * dx + dz * dz;
      if (at >= bestAt) continue;
      if (reachable != null && !reachable(cellX, cellZ)) continue;
      best = cell;
      bestAt = at;
    }
    return best;
  }

  /// A cell's middle as a point, for a caller that wants somewhere to walk.
  Vector3 centreOf(int cell) => Vector3(centreX(cell), 0.0, centreZ(cell));

  /// What every side knows, as one string, plus the shape of the lattice it
  /// was written on.
  ///
  /// **Base64 rather than a list of numbers**, because the lattice is one byte
  /// a cell a side and a demo map is a few thousand cells: written out as JSON
  /// numbers that is tens of kilobytes of `1,3,1,1,` where the same bytes are a
  /// few kilobytes of text, and every one of those numbers would have to be
  /// read back and range-checked one at a time.
  ///
  /// The three counts are not state and are saved anyway: they are how
  /// [restore] tells a save of *this* map from a save of another one. Without
  /// them a lattice from a wider map lands here as a stripe of knowledge
  /// shifted a few cells sideways per row — a fog that is wrong in a way that
  /// looks like weather.
  Map<String, Object?> save() => <String, Object?>{
    'columns': columns,
    'rows': rows,
    'sides': sides,
    'state': base64Encode(_state),
  };

  /// Puts [from] back, or leaves this lattice alone when it does not fit.
  ///
  /// Written into the array that is already here rather than swapped for a new
  /// one: the drawing half holds this fog, and a lattice replaced underneath it
  /// is a picture that stops following the rules it is meant to be showing.
  ///
  /// Left alone rather than thrown over, for the reason [Snapshot] gives about
  /// documents from other builds — and a fog that stays as it is, is a fog the
  /// next refresh corrects.
  void restore(Map<String, Object?> from) {
    if (from.integer('columns', -1) != columns) return;
    if (from.integer('rows', -1) != rows) return;
    if (from.integer('sides', -1) != sides) return;
    final String? written = from.text('state');
    if (written == null) return;
    final Uint8List bytes;
    try {
      bytes = base64Decode(written);
    } on FormatException {
      // A string that is not base64 at all — a truncated write, a hand edit.
      // The same answer as a lattice of the wrong size, and for the same
      // reason: a save file is the document that must not refuse to load.
      return;
    }
    if (bytes.length != _state.length) return;
    _state.setAll(0, bytes);
  }
}
