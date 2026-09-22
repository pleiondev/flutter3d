/// Tiles, levels and skirts for a heightfield — `gfx-87n`.
///
///     dart test test/heightfield_tiles_test.dart
///
/// The geometry half, checked where it can be checked without a renderer: the
/// skirt is deep enough to cover the worst gap two levels can open, and a tile's
/// level follows the camera without flipping on a slow approach. Whether a
/// crack actually shows is `flutter3d_app`'s `terrain_tiles_test.dart`, which
/// draws one.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// Rolling ground: a few long waves and one short one, so coarse levels
/// genuinely disagree with fine ones along every edge.
Heightfield _rolling({int cells = 32, double cell = 1.0}) {
  final side = cells + 1;
  final heights = Float32List(side * side);
  for (var r = 0; r < side; r++) {
    for (var c = 0; c < side; c++) {
      heights[r * side + c] =
          2.0 * math.sin(c * 0.3) * math.cos(r * 0.2) +
          0.6 * math.sin(c * 1.7 + r * 1.3);
    }
  }
  return Heightfield(
    columns: side,
    rows: side,
    cellSize: cell,
    heights: heights,
  );
}

/// The height the line along one tile edge at [level] gives at every sample,
/// against the samples themselves.
double _worstEdgeGap(HeightfieldTiles tiles, int levelA, int levelB) {
  final field = tiles.field;
  var worst = 0.0;
  // The shared edge at column = one tile in, every row: tile (0, z) on the
  // left at levelA, tile (1, z) on the right at levelB.
  final c = tiles.tileCells;
  double along(int level, int row) {
    final step = 1 << level;
    final start = (row ~/ step) * step;
    final end = math.min(start + step, field.rows - 1);
    if (start == end) return field.sample(c, start);
    final t = (row - start) / (end - start);
    return field.sample(c, start) +
        (field.sample(c, end) - field.sample(c, start)) * t;
  }

  for (var row = 0; row < field.rows; row++) {
    worst = math.max(worst, (along(levelA, row) - along(levelB, row)).abs());
  }
  return worst;
}

void main() {
  group('a tile at a level', () {
    final tiles = HeightfieldTiles(_rolling(), tileCells: 16, levels: 4);

    test('keeps every 2^level-th sample, and the skirt around it', () {
      for (var level = 0; level < 4; level++) {
        final side = 16 ~/ (1 << level) + 1;
        final surface = tiles.build(0, 0, level: level, material: 'ground');
        expect(
          surface.positions.length ~/ 3,
          side * side + 4 * side,
          reason: 'level $level',
        );
        final plain = tiles.build(
          0,
          0,
          level: level,
          material: 'ground',
          skirts: false,
        );
        expect(plain.positions.length ~/ 3, side * side);
        expect(plain.indices.length, (side - 1) * (side - 1) * 6);
      }
    });

    test('its grid vertices sit on the field', () {
      // A coarse tile is a subset of the samples, not an average of them: a
      // vertex that moved would put the tile's edge off the line its neighbour
      // is drawing, which is a crack before any level difference.
      final surface = tiles.build(
        1,
        1,
        level: 2,
        material: 'ground',
        skirts: false,
      );
      final field = tiles.field;
      for (var v = 0; v < surface.positions.length ~/ 3; v++) {
        final x = surface.positions[v * 3];
        final y = surface.positions[v * 3 + 1];
        final z = surface.positions[v * 3 + 2];
        final column = (x / field.cellSize).round();
        final row = (z / field.cellSize).round();
        expect(y, field.sample(column, row), reason: 'vertex $v');
      }
    });

    test('the skirt reaches past the worst gap any two levels open', () {
      // Every pair of levels on the one edge measured directly — the same
      // question `skirtDepth` answers from the other side, so the two can
      // disagree only if one of them is wrong.
      var worst = 0.0;
      for (var a = 0; a < 4; a++) {
        for (var b = a + 1; b < 4; b++) {
          worst = math.max(worst, _worstEdgeGap(tiles, a, b));
        }
      }
      expect(worst, greaterThan(0.1), reason: 'the field is too flat to test');
      expect(tiles.skirtDepth, greaterThanOrEqualTo(worst));
    });

    test('a tile\'s bounds hold its highest and lowest sample', () {
      final box = tiles.bounds(1, 0);
      final field = tiles.field;
      var low = double.infinity, high = -double.infinity;
      for (var r = 0; r <= 16; r++) {
        for (var c = 16; c <= 32; c++) {
          low = math.min(low, field.sample(c, r));
          high = math.max(high, field.sample(c, r));
        }
      }
      expect(box.min.y, low);
      expect(box.max.y, high);
      expect(box.min.x, 16.0);
      expect(box.max.x, 32.0);
    });
  });

  group('what cannot be tiled is refused', () {
    test('a tile that is not a power of two', () {
      expect(
        () => HeightfieldTiles(_rolling(), tileCells: 12, levels: 2),
        throwsArgumentError,
      );
    });

    test('a field that is not whole tiles', () {
      expect(
        () => HeightfieldTiles(_rolling(cells: 30), tileCells: 16, levels: 2),
        throwsArgumentError,
      );
    });

    test('more levels than a tile has cells', () {
      expect(
        () => HeightfieldTiles(_rolling(), tileCells: 4, levels: 4),
        throwsArgumentError,
      );
    });
  });

  group('the level follows the camera', () {
    const chooser = TileLevelChooser(nearest: 20, levels: 4);

    test('with no memory, doubling the distance is one level coarser', () {
      expect(chooser.choose(10, null), 0);
      expect(chooser.choose(30, null), 1);
      expect(chooser.choose(70, null), 2);
      expect(chooser.choose(500, null), 3);
    });

    test('a slow approach across a threshold changes level once', () {
      // From 30 metres to 10, a centimetre a frame: the threshold between
      // levels 1 and 0 is at 20, and a chooser with no band would decide at
      // exactly 20.0 and then again at every rounding of it.
      var level = chooser.choose(30, null);
      var changes = 0;
      for (var d = 30.0; d > 10.0; d -= 0.01) {
        final next = chooser.choose(d, level);
        if (next != level) changes++;
        level = next;
      }
      expect(level, 0);
      expect(changes, 1);
    });

    test('a camera hovering on a threshold does not flip', () {
      // Swaying half a metre either side of 20, which is inside the band both
      // ways: whichever level the tile had, it keeps.
      for (final start in <int>[0, 1]) {
        var level = start;
        for (var frame = 0; frame < 400; frame++) {
          final d = 20 + 0.5 * math.sin(frame * 0.1);
          level = chooser.choose(d, level);
        }
        expect(level, start, reason: 'started at $start');
      }
    });

    test('a teleport lands on the right level in one frame', () {
      expect(chooser.choose(500, 0), 3);
      expect(chooser.choose(5, 3), 0);
    });
  });
}
