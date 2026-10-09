/// A grid of cells that are there or not, and the blocks they are drawn as.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'box_shapes.dart';
import 'mesh_data.dart';

/// [columns] by [rows] cells, each there or gone: a Space Invaders shield,
/// a wall of bricks, a field of crops.
///
/// **Made to be worn away.** A shield loses a few cells to every shot and
/// is drawn again from what is left; [clear] and [clearAround] take cells
/// away, and [mesh] draws the ones still there as blocks.
final class CellGrid {
  CellGrid({required this.columns, required this.rows, this.cell = 1.0})
    : _alive = Uint8List(columns * rows) {
    if (columns <= 0 || rows <= 0) throw ArgumentError('A grid of nothing.');
  }

  /// A grid from lines of text, one per row, `#` for a cell and anything
  /// else for none; rows shorter than the longest are empty past their end.
  factory CellGrid.fromMask(List<String> mask, {double cell = 1.0}) {
    final columns = mask.fold<int>(
      0,
      (w, line) => w > line.length ? w : line.length,
    );
    final grid = CellGrid(columns: columns, rows: mask.length, cell: cell);
    for (var r = 0; r < mask.length; r++) {
      for (var c = 0; c < mask[r].length; c++) {
        if (mask[r][c] == '#') grid._alive[r * columns + c] = 1;
      }
    }
    return grid;
  }

  final int columns;
  final int rows;

  /// The size of one cell, in metres.
  final double cell;

  final Uint8List _alive;

  /// How many cells are there.
  int get count => _alive.fold<int>(0, (n, v) => n + v);

  /// Whether cell ([column], [row]) is there; outside the grid, no.
  bool isAlive(int column, int row) =>
      column >= 0 &&
      row >= 0 &&
      column < columns &&
      row < rows &&
      _alive[row * columns + column] == 1;

  /// Takes cell ([column], [row]) away. True when it was there.
  bool clear(int column, int row) {
    if (!isAlive(column, row)) return false;
    _alive[row * columns + column] = 0;
    return true;
  }

  /// Puts cell ([column], [row]) there, or takes it away when [alive] is
  /// false. True when that changed it; a cell outside the grid is left.
  ///
  /// **Grown as well as worn.** A trail laid behind a cycle, a wall read
  /// from a level: a grid that could only lose cells was built once from a
  /// mask and never had one added.
  bool set(int column, int row, {bool alive = true}) {
    if (column < 0 || row < 0 || column >= columns || row >= rows) {
      return false;
    }
    final at = row * columns + column;
    final value = alive ? 1 : 0;
    if (_alive[at] == value) return false;
    _alive[at] = value;
    return true;
  }

  /// Takes away every cell whose middle is within [radius] metres of
  /// ([x], [y]), measured from the grid's corner. How many went.
  int clearAround(double x, double y, double radius) {
    var gone = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        final dx = (c + 0.5) * cell - x;
        final dy = (r + 0.5) * cell - y;
        if (dx * dx + dy * dy <= radius * radius && clear(c, r)) gone++;
      }
    }
    return gone;
  }

  /// The cells still there as blocks [depth] deep, merged into one mesh;
  /// null when none are left.
  /// [place] says where a cell's middle goes, from its middle's (x, y) in
  /// metres from the grid's corner; the block is centred on that point.
  MeshData? mesh({
    required Vector3 Function(double x, double y) place,
    double? depth,
    Vector4? colour,
  }) {
    final size = Vector3(cell, depth ?? cell, cell);
    final block = CuboidShape(size: size).build();
    final parts = <MeshData>[
      for (var r = 0; r < rows; r++)
        for (var c = 0; c < columns; c++)
          if (_alive[r * columns + c] == 1)
            block.transformed(
              Matrix4.translation(place((c + 0.5) * cell, (r + 0.5) * cell)),
            ),
    ];
    if (parts.isEmpty) return null;
    final merged = MeshData.merge(parts);
    return colour == null ? merged : merged.withColor(colour);
  }
}
