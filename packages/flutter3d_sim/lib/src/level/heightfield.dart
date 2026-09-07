/// A grid of heights, and the surface it stands for.
///
/// **The first sloped ground this format has.** A `Brush` is a box, and
/// `nav_grid.dart` says as much where it explains what it cannot bake: the
/// level format has had no sloped surfaces except the ramp a wedge makes. A
/// strategy is played on ground that rises, so the ground becomes a field of
/// samples with a surface stretched over them.
///
/// **Heights, not geometry.** This knows what the ground is and answers
/// questions about it — how high, which way it faces, how steep. It builds no
/// mesh and names no renderer, the way `brush_geometry.dart` next door emits
/// faces rather than vertices: the bridge is what turns either into something
/// drawn, and it is the only package that sees both sides.
///
/// ## The surface is triangles, so the answers are too
///
/// Four samples make a quad and a quad is drawn as two triangles, which means
/// **a quad is not flat** unless its corners happen to agree. Between them
/// bilinear interpolation describes a curved sheet that no triangle follows,
/// and every question answered that way is answered about a surface nobody
/// draws: a unit placed by it hovers over one half of the quad and sinks into
/// the other, by up to a quarter of the corner spread. So [heightAt] finds the
/// triangle the point is in and interpolates across that, and [normalAt]
/// returns that triangle's own normal.
///
/// **The diagonal is fixed and shared.** A quad can be split two ways and the
/// two disagree about the middle, so the split has to be one decision made in
/// one place: `(0,0)–(1,1)`, the corner nearest the origin joined to the one
/// furthest. A mesh builder that splits the other way draws a surface this
/// class does not describe, and nothing would catch it but a unit standing in
/// the air, so the rule is written here and the builder follows it rather than
/// choosing again.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../math/portable_math.dart';

/// Ground as a grid of sampled heights.
final class Heightfield {
  /// Builds a field from [heights], row-major, `columns * rows` of them.
  ///
  /// [origin] is where sample `(0, 0)` sits in the world; the field extends
  /// along +X and +Z from there.
  Heightfield({
    required this.columns,
    required this.rows,
    required this.cellSize,
    required Float32List heights,
    Vector3? origin,
  }) : assert(columns > 1 && rows > 1, 'a field of one sample has no surface'),
       assert(cellSize > 0.0, 'a cell of no width has no place to stand'),
       assert(
         heights.length == columns * rows,
         'the field is columns * rows samples and nothing else',
       ),
       _heights = heights,
       origin = origin ?? Vector3.zero();

  /// Reads a field from a level document's `heightfield` section.
  ///
  /// Heights arrive as base64 of the bytes of a `Float32List`, the way
  /// `LevelVisibility` carries its cells: sixteen thousand numbers written out
  /// as JSON text is a megabyte of digits that nobody reads and every editor
  /// reformats. The rest of the section is plain, because the rest of it is
  /// four numbers a person might want to change by hand.
  factory Heightfield.fromJson(Map<String, Object?> json) {
    final int columns = (json['columns'] as num?)?.toInt() ?? 0;
    final int rows = (json['rows'] as num?)?.toInt() ?? 0;
    final Object? heights = json['heights'];
    if (columns < 2 || rows < 2 || heights is! String) {
      throw const FormatException(
        'a heightfield is columns, rows and base64 heights, and needs at '
        'least two samples along each axis to have a surface',
      );
    }
    final Uint8List bytes = base64Decode(heights);
    if (bytes.length != columns * rows * 4) {
      throw FormatException(
        'the field says ${columns}x$rows samples and carries '
        '${bytes.length ~/ 4} of them',
      );
    }
    final origin = json['origin'];
    return Heightfield(
      columns: columns,
      rows: rows,
      cellSize: (json['cellSize'] as num?)?.toDouble() ?? 1.0,
      heights: Float32List.view(Uint8List.fromList(bytes).buffer),
      origin: origin is List && origin.length == 3
          ? Vector3(
              (origin[0] as num).toDouble(),
              (origin[1] as num).toDouble(),
              (origin[2] as num).toDouble(),
            )
          : null,
    );
  }

  /// The section as a level document carries it.
  Map<String, Object?> toJson() => <String, Object?>{
    'columns': columns,
    'rows': rows,
    'cellSize': cellSize,
    if (origin.x != 0.0 || origin.y != 0.0 || origin.z != 0.0)
      'origin': <double>[origin.x, origin.y, origin.z],
    'heights': base64Encode(_heights.buffer.asUint8List()),
  };

  /// Samples along +X.
  final int columns;

  /// Samples along +Z.
  final int rows;

  /// Metres between neighbouring samples, the same along both axes.
  final double cellSize;

  /// Where sample `(0, 0)` is, in world space.
  final Vector3 origin;

  final Float32List _heights;

  /// How far the field reaches along +X, in metres.
  double get width => (columns - 1) * cellSize;

  /// How far the field reaches along +Z, in metres.
  double get depth => (rows - 1) * cellSize;

  /// The height at sample [column], [row].
  double sample(int column, int row) => _heights[row * columns + column];

  /// Whether `(x, z)` is over the field at all.
  bool contains(double x, double z) {
    final double u = x - origin.x;
    final double v = z - origin.z;
    return u >= 0.0 && v >= 0.0 && u <= width && v <= depth;
  }

  /// The height of the drawn surface under `(x, z)`.
  ///
  /// Outside the field this is the nearest edge's height rather than a throw or
  /// a nought: a unit walking off the map should meet the edge it can see, and
  /// a zero here is a cliff to the origin plane that exists in no picture.
  double heightAt(double x, double z) {
    final _Cell cell = _cellAt(x, z);
    // Corner heights, named for where they sit in the cell.
    final double h00 = sample(cell.column, cell.row);
    final double h10 = sample(cell.column + 1, cell.row);
    final double h01 = sample(cell.column, cell.row + 1);
    final double h11 = sample(cell.column + 1, cell.row + 1);

    // The diagonal runs (0,0)–(1,1). Below it — where the distance along X is
    // the greater — the triangle is (0,0), (1,0), (1,1); above it, (0,0),
    // (0,1), (1,1). Both are written as a plane through the corner they share.
    if (cell.u >= cell.v) {
      return h00 + (h10 - h00) * cell.u + (h11 - h10) * cell.v;
    }
    return h00 + (h11 - h01) * cell.u + (h01 - h00) * cell.v;
  }

  /// The normal of the triangle under `(x, z)`, into [out].
  ///
  /// The triangle's own normal, flat across it, because that is the face a body
  /// rests on. A normal averaged between neighbours is a shading normal: it
  /// makes a smooth picture and would put a body at an angle no drawn triangle
  /// holds.
  void normalAt(double x, double z, Vector3 out) {
    final _Cell cell = _cellAt(x, z);
    final double h00 = sample(cell.column, cell.row);
    final double h10 = sample(cell.column + 1, cell.row);
    final double h01 = sample(cell.column, cell.row + 1);
    final double h11 = sample(cell.column + 1, cell.row + 1);

    // Two edges of the triangle, crossed. Written out rather than built as
    // vectors: this is called per body per step, and three temporaries a call
    // is the sort of thing that shows up in a profile of a crowd.
    final double s = cellSize;
    final double ax, az, ay, bx, bz, by;
    if (cell.u >= cell.v) {
      ax = s;
      ay = h10 - h00;
      az = 0.0;
      bx = s;
      by = h11 - h00;
      bz = s;
    } else {
      ax = 0.0;
      ay = h01 - h00;
      az = s;
      bx = s;
      by = h11 - h00;
      bz = s;
    }
    out
      ..x = ay * bz - az * by
      ..y = az * bx - ax * bz
      ..z = ax * by - ay * bx;
    if (out.y < 0.0) out.negate();
    out.normalize();
  }

  /// How steep the ground is under `(x, z)`, in radians from flat.
  ///
  /// Zero on the level and `pi / 2` on a wall. What a walkable slope is belongs
  /// to whoever is walking — a tank and a scout disagree — so this reports the
  /// angle and refuses to have an opinion about it.
  ///
  /// **`atan2` of the horizontal against the vertical rather than `acos` of the
  /// vertical**, and the structure rule `a step asks no machine for an answer`
  /// is what asked for it: `math.acos` is the platform's libm, so a run
  /// verified in a browser would disagree with the run a player made — and
  /// `Portable` has no `acos` to reach for instead. For a unit normal the two
  /// are the same angle, and this one is better conditioned near flat, where
  /// `acos` of a number a hair over one is where the domain error lives.
  double slopeAt(double x, double z) {
    final Vector3 normal = Vector3.zero();
    normalAt(x, z, normal);
    final double flatness = math.sqrt(
      normal.x * normal.x + normal.z * normal.z,
    );
    return Portable.atan2(flatness, normal.y);
  }

  /// Which cell holds `(x, z)`, and where in it.
  ///
  /// **The cell and the fraction are clamped separately, and the first version
  /// clamped them together.** Holding the coordinate just short of the last
  /// sample — `columns - 1.0001` — keeps the index in range and leaves the
  /// fraction at 0.9999, so a point far off the edge came back a ten-thousandth
  /// below the edge it was supposed to meet. Small, permanent, and exactly the
  /// kind of thing that is read as noise in a profile rather than as a bug.
  _Cell _cellAt(double x, double z) {
    final double u = (x - origin.x) / cellSize;
    final double v = (z - origin.z) / cellSize;
    final int column = u.floor().clamp(0, columns - 2);
    final int row = v.floor().clamp(0, rows - 2);
    return _Cell(
      column,
      row,
      (u - column).clamp(0.0, 1.0),
      (v - row).clamp(0.0, 1.0),
    );
  }
}

/// Which cell a point fell in, and where inside it.
final class _Cell {
  const _Cell(this.column, this.row, this.u, this.v);

  final int column;
  final int row;

  /// Where across the cell the point is, from zero to one.
  final double u;
  final double v;
}
