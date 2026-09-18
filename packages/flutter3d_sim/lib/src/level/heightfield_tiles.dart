/// A [Heightfield] cut into tiles, each at a level of detail, with no crack
/// where two levels meet — `gfx-87n`.
///
/// **What [HeightfieldGeometry] does not do, and why it stops being enough.**
/// That builder draws the whole field as one surface at full resolution, which
/// is right for a strategy map a few hundred samples across and wrong for
/// ground that runs to the horizon: every sample is drawn whether it covers a
/// hundred pixels or a tenth of one. So the field is cut into square tiles and
/// each is built at several resolutions — level `l` keeps every `2^l`-th
/// sample — and the application draws near tiles fine and far ones coarse.
///
/// **The seam is the whole problem.** A fine tile's edge follows every sample
/// along it; a coarse neighbour's edge is a straight line between every fourth.
/// Where the ground bends between them, the two edges part, and the sky shows
/// through a crack that opens and shuts as the camera moves and levels change.
/// The cheap and complete answer is a **skirt**: each tile's edge is copied
/// straight down and the two joined with a strip, so whatever gap opens at a
/// seam has ground behind it. Stitching — rewriting the fine tile's edge to
/// match its neighbour — closes the crack exactly, but it makes every tile's
/// triangles depend on its neighbours' levels, so a change of level rebuilds
/// four tiles instead of one.
///
/// **How deep is computed, not guessed.** [skirtDepth] is the largest distance
/// any level's edge strays from the full-resolution one, anywhere on the field,
/// doubled — two neighbours can each stray the full amount in opposite
/// directions. A fixed depth is either too shallow on a cliff or a wall of
/// ground hanging under every tile on a plain.
///
/// **The diagonal is the one [Heightfield] fixed**, `(0,0)–(1,1)`, at every
/// level, for the reason `heightfield_geometry.dart` gives: a builder that split
/// a quad the other way would draw ground the field does not describe.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'brush.dart';
import 'brush_surface.dart';
import 'heightfield.dart';

/// A field cut into tiles of [tileCells] cells a side, each buildable at any
/// of [levels] resolutions.
final class HeightfieldTiles {
  /// Cuts [field] into tiles.
  ///
  /// Throws [ArgumentError] unless [tileCells] is a power of two, the field's
  /// cells divide into whole tiles both ways, and the coarsest level still has
  /// at least one cell a tile. A partial tile at the far edge would be a tile
  /// whose coarse levels fall between samples, and a level that skipped more
  /// cells than a tile has would be a tile of no triangles.
  HeightfieldTiles(this.field, {required this.tileCells, required this.levels})
    : tilesX = (field.columns - 1) ~/ tileCells,
      tilesZ = (field.rows - 1) ~/ tileCells {
    if (tileCells < 1 || tileCells & (tileCells - 1) != 0) {
      throw ArgumentError('A tile is a power of two cells; $tileCells is not.');
    }
    if ((field.columns - 1) % tileCells != 0 ||
        (field.rows - 1) % tileCells != 0) {
      throw ArgumentError(
        'The field is ${field.columns - 1} by ${field.rows - 1} cells, which '
        'is not whole $tileCells-cell tiles.',
      );
    }
    if (levels < 1 || (1 << (levels - 1)) > tileCells) {
      throw ArgumentError(
        '$levels levels would skip ${1 << (levels - 1)} cells at the coarsest, '
        'and a tile is $tileCells.',
      );
    }
  }

  final Heightfield field;
  final int tileCells;
  final int levels;

  /// Tiles along X.
  final int tilesX;

  /// Tiles along Z.
  final int tilesZ;

  /// How far each tile's edge is copied down — see the library comment.
  late final double skirtDepth = _measureSkirtDepth();

  /// The box [tileX], [tileZ] occupies, highest and lowest sample included, so
  /// a distance to it is a distance to ground and not to a plane under it.
  Aabb3 bounds(int tileX, int tileZ) {
    final c0 = tileX * tileCells;
    final r0 = tileZ * tileCells;
    var low = double.infinity;
    var high = -double.infinity;
    for (var r = r0; r <= r0 + tileCells; r++) {
      for (var c = c0; c <= c0 + tileCells; c++) {
        final h = field.sample(c, r);
        if (h < low) low = h;
        if (h > high) high = h;
      }
    }
    final cell = field.cellSize;
    return Aabb3.minMax(
      Vector3(field.origin.x + c0 * cell, low, field.origin.z + r0 * cell),
      Vector3(
        field.origin.x + (c0 + tileCells) * cell,
        high,
        field.origin.z + (r0 + tileCells) * cell,
      ),
    );
  }

  /// Tile [tileX], [tileZ] at [level], keeping every `2^level`-th sample.
  ///
  /// [skirts] off is for a field drawn at one level everywhere, where no seam
  /// ever opens — and for the test that shows the crack a skirt closes.
  BrushSurface build(
    int tileX,
    int tileZ, {
    required int level,
    required String material,
    double metresPerTexture = 8.0,
    bool skirts = true,
    ShadowCasting shadowCasting = ShadowCasting.on,
  }) {
    if (level < 0 || level >= levels) {
      throw RangeError.range(level, 0, levels - 1, 'level');
    }
    final step = 1 << level;
    final side = tileCells ~/ step + 1;
    final c0 = tileX * tileCells;
    final r0 = tileZ * tileCells;

    // The grid, then four skirts of `side` vertices each.
    final gridVertices = side * side;
    final vertexCount = gridVertices + (skirts ? 4 * side : 0);
    final positions = Float32List(vertexCount * 3);
    final normals = Float32List(vertexCount * 3);
    final texcoords = Float32List(vertexCount * 2);
    final tangents = Float32List(vertexCount * 4);

    void put(int v, int column, int row, double drop) {
      final cell = field.cellSize;
      final x = field.origin.x + column * cell;
      final z = field.origin.z + row * cell;
      positions
        ..[v * 3] = x
        ..[v * 3 + 1] = field.sample(column, row) - drop
        ..[v * 3 + 2] = z;
      _shade(column, row, normals, tangents, v);
      texcoords
        ..[v * 2] = x / metresPerTexture
        ..[v * 2 + 1] = z / metresPerTexture;
    }

    for (var j = 0; j < side; j++) {
      for (var i = 0; i < side; i++) {
        put(j * side + i, c0 + i * step, r0 + j * step, 0);
      }
    }

    final cells = side - 1;
    final gridIndices = cells * cells * 6;
    final skirtIndices = skirts ? 4 * cells * 12 : 0;
    final indices = Uint32List(gridIndices + skirtIndices);
    var at = 0;
    for (var j = 0; j < cells; j++) {
      for (var i = 0; i < cells; i++) {
        final v00 = j * side + i;
        final v10 = v00 + 1;
        final v01 = v00 + side;
        final v11 = v01 + 1;
        // The winding and the diagonal `heightfield_geometry.dart` uses.
        indices
          ..[at++] = v00
          ..[at++] = v11
          ..[at++] = v10
          ..[at++] = v00
          ..[at++] = v01
          ..[at++] = v11;
      }
    }

    if (skirts) {
      // The four edges, each as the grid indices along it; the lowered copy of
      // edge `e` starts at `gridVertices + e * side`.
      final edges = <List<int>>[
        <int>[for (var i = 0; i < side; i++) i], // row 0
        <int>[for (var i = 0; i < side; i++) (side - 1) * side + i], // last row
        <int>[for (var j = 0; j < side; j++) j * side], // column 0
        <int>[
          for (var j = 0; j < side; j++) j * side + side - 1,
        ], // last column
      ];
      for (var e = 0; e < 4; e++) {
        final base = gridVertices + e * side;
        for (var k = 0; k < side; k++) {
          final top = edges[e][k];
          final column = c0 + (top % side) * step;
          final row = r0 + (top ~/ side) * step;
          put(base + k, column, row, skirtDepth);
        }
        // Both windings. Which side of a skirt faces outward depends on which
        // edge it hangs from and which way the camera looks along it; drawing
        // both is a strip of a few dozen triangles a tile, and it cannot be
        // the one face culled when the crack it exists for is showing.
        for (var k = 0; k < cells; k++) {
          final a = edges[e][k];
          final b = edges[e][k + 1];
          final la = base + k;
          final lb = base + k + 1;
          indices
            ..[at++] = a
            ..[at++] = la
            ..[at++] = b
            ..[at++] = b
            ..[at++] = la
            ..[at++] = lb
            ..[at++] = a
            ..[at++] = b
            ..[at++] = la
            ..[at++] = b
            ..[at++] = lb
            ..[at++] = la;
        }
      }
    }

    return BrushSurface(
      material: material,
      shadowCasting: shadowCasting,
      positions: positions,
      normals: normals,
      texcoords: texcoords,
      tangents: tangents,
      indices: indices,
    );
  }

  /// The normal and tangent at a sample, from the full-resolution field.
  ///
  /// **Full resolution at every level, on purpose.** A coarse tile's vertex
  /// sits on a sample the fine neighbour also has; shading it from the coarse
  /// grid's own neighbours would give the two the same position and different
  /// normals, and the seam that the skirt closed in the geometry would open
  /// again in the lighting as a line of changed shade.
  void _shade(
    int column,
    int row,
    Float32List normals,
    Float32List tangents,
    int v,
  ) {
    final columns = field.columns;
    final rows = field.rows;
    final cell = field.cellSize;
    final left = math.max(column - 1, 0);
    final right = math.min(column + 1, columns - 1);
    final near = math.max(row - 1, 0);
    final far = math.min(row + 1, rows - 1);
    final dx = field.sample(right, row) - field.sample(left, row);
    final dz = field.sample(column, far) - field.sample(column, near);
    final spanX = (right - left) * cell;
    final spanZ = (far - near) * cell;

    final nx = -dx * spanZ;
    final ny = spanX * spanZ;
    final nz = -dz * spanX;
    final length = math.sqrt(nx * nx + ny * ny + nz * nz);
    normals
      ..[v * 3] = nx / length
      ..[v * 3 + 1] = ny / length
      ..[v * 3 + 2] = nz / length;

    final tLength = math.sqrt(spanX * spanX + dx * dx);
    tangents
      ..[v * 4] = spanX / tLength
      ..[v * 4 + 1] = dx / tLength
      ..[v * 4 + 2] = 0.0
      ..[v * 4 + 3] = 1.0;
  }

  double _measureSkirtDepth() {
    // Every tile edge lies on one of these lines — the rows and columns that
    // are multiples of a tile — so measuring along the lines measures every
    // edge once, shared edges included.
    var worst = 0.0;
    for (var level = 1; level < levels; level++) {
      final step = 1 << level;
      for (var r = 0; r < field.rows; r += tileCells) {
        worst = math.max(
          worst,
          _stray(step, (i) => field.sample(i, r), field.columns),
        );
      }
      for (var c = 0; c < field.columns; c += tileCells) {
        worst = math.max(
          worst,
          _stray(step, (j) => field.sample(c, j), field.rows),
        );
      }
    }
    // Doubled because two neighbours can stray in opposite directions, and
    // never nothing: a field flat enough to need no skirt still has float
    // rounding at the seam, which shows as single pixels of sky.
    return math.max(worst * 2, field.cellSize * 0.01);
  }

  /// How far the line through every [step]-th sample strays from the samples
  /// between.
  double _stray(int step, double Function(int) height, int count) {
    var worst = 0.0;
    for (var start = 0; start + step < count; start += step) {
      final a = height(start);
      final b = height(start + step);
      for (var k = 1; k < step; k++) {
        final line = a + (b - a) * k / step;
        worst = math.max(worst, (height(start + k) - line).abs());
      }
    }
    return worst;
  }
}

/// Which level each tile draws at, from how far it is — with hysteresis.
///
/// **Level `l` is right out to `nearest * 2^l` metres.** Each level has half
/// the samples of the one before, so doubling the distance keeps a cell about
/// the same number of pixels on screen.
///
/// **A band around each threshold, so a slow approach changes level once.**
/// A tile whose distance sat on a threshold would flip between two levels
/// every frame the camera drifted across it, and the ground would visibly
/// shimmer between two shapes. Moving to a coarser level waits until the tile
/// is [band] beyond the threshold, and moving back waits until it is [band]
/// inside; in between, it keeps whatever it had.
final class TileLevelChooser {
  const TileLevelChooser({
    required this.nearest,
    required this.levels,
    this.band = 0.15,
  });

  /// How far level 0 reaches, in metres.
  final double nearest;
  final int levels;

  /// The fraction of a threshold a tile has to cross it by.
  final double band;

  /// The level a tile at [distance] should draw at, given it drew at
  /// [current] last frame. Pass null for a tile drawn for the first time,
  /// which has nothing to keep.
  int choose(double distance, int? current) {
    // Where the distance falls with no memory at all: the first threshold it
    // has not passed.
    var plain = 0;
    while (plain < levels - 1 && distance > nearest * (1 << plain)) {
      plain++;
    }
    if (current == null) return plain;

    var level = current;
    // Coarser only once clearly past the threshold that separates the two.
    while (level < levels - 1 &&
        distance > nearest * (1 << level) * (1 + band)) {
      level++;
    }
    // Finer only once clearly inside it.
    while (level > 0 && distance < nearest * (1 << (level - 1)) * (1 - band)) {
      level--;
    }
    return level;
  }
}
