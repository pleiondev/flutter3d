/// The level as columns of solid voxels, and the filters that decide which
/// tops of them are floors.
///
/// **Sampled at cell centres, the way `NavGrid` samples.** A brush gives a
/// column a floor only when the column's centre is inside it; a brush that
/// only clips the column still fills it, as a span nobody stands on. That is
/// `NavGrid`'s rule — a thin wall crossing a cell blocks it even when no
/// centre lands inside — said in spans, and it is why the two bakes of one
/// level can be held against each other cell by cell.
library;

import 'dart:math' as math;

import '../../level/brush.dart';
import '../../level/heightfield.dart';
import '../../math/portable_math.dart';
import '../../math/tolerances.dart';
import 'navmesh_config.dart';

/// The area of a span nobody walks on.
const int nullArea = 0;

/// One run of solid voxels in a column, `[min, max)` in voxels.
final class SolidSpan {
  SolidSpan(this.min, this.max, this.area);

  final int min;
  final int max;

  /// What the top of this span is, as a walking surface; [nullArea] when it
  /// is not one. The one field the filters change.
  int area;
}

/// The lattice a mesh is baked on: where its corner is and how many cells.
///
/// Taken from the level when a mesh is first baked — its corner at the least
/// x and z any solid brush reaches, its count the extent over the cell size
/// rounded up, terrain widening it — and kept by the mesh, so that a part of
/// it baked again later lands on the same cells.
final class NavLattice {
  const NavLattice({
    required this.originX,
    required this.originY,
    required this.originZ,
    required this.columns,
    required this.rows,
  });

  /// Nothing to stand on: no columns.
  static const NavLattice empty = NavLattice(
    originX: 0.0,
    originY: 0.0,
    originZ: 0.0,
    columns: 0,
    rows: 0,
  );

  /// The world position of voxel `(0, 0, 0)`'s lowest corner.
  final double originX;
  final double originY;
  final double originZ;

  final int columns;
  final int rows;

  bool get isEmpty => columns == 0 || rows == 0;

  /// The lattice of [brushes]' solid ones and [ground] — `NavGrid.bake`'s.
  factory NavLattice.of(
    Iterable<Brush> brushes, {
    required NavMeshConfig config,
    Heightfield? ground,
  }) {
    final solid = <Brush>[
      for (final brush in brushes)
        if (brush.solid) brush,
    ];
    if (solid.isEmpty && ground == null) return empty;
    final samples = ground?.copyOfSamples();
    final groundLow = samples == null || samples.isEmpty
        ? null
        : samples.reduce(math.min).toDouble();
    final (minX, minY, minZ, maxX, maxZ) = solid.fold(
      ground == null
          ? (
              double.infinity,
              double.infinity,
              double.infinity,
              double.negativeInfinity,
              double.negativeInfinity,
            )
          : (
              ground.origin.x,
              groundLow!,
              ground.origin.z,
              ground.origin.x + ground.width,
              ground.origin.z + ground.depth,
            ),
      (box, brush) => (
        math.min(box.$1, brush.min.x),
        math.min(box.$2, brush.min.y),
        math.min(box.$3, brush.min.z),
        math.max(box.$4, brush.max.x),
        math.max(box.$5, brush.max.z),
      ),
    );
    final cs = config.cellSize;
    return NavLattice(
      originX: minX,
      originY: minY,
      originZ: minZ,
      columns: math.max(1, ((maxX - minX) / cs).ceil()),
      rows: math.max(1, ((maxZ - minZ) / cs).ceil()),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NavLattice &&
      other.originX == originX &&
      other.originY == originY &&
      other.originZ == originZ &&
      other.columns == columns &&
      other.rows == rows;

  @override
  int get hashCode => Object.hash(originX, originY, originZ, columns, rows);
}

/// A rectangle of a lattice's columns, `[x0, x1)` by `[z0, z1)`.
typedef NavWindow = ({int x0, int z0, int x1, int z1});

/// Solid voxels, column by column, lowest span first.
final class SpanField {
  SpanField._({
    required this.originX,
    required this.originY,
    required this.originZ,
    required this.cellSize,
    required this.cellHeight,
    required this.columns,
    required this.rows,
    required this.offsetX,
    required this.offsetZ,
    required this.spans,
  });

  /// The world position of the lattice's voxel `(0, 0, 0)`'s lowest corner —
  /// the lattice's, not this field's first column's, when the field is a
  /// window onto it.
  final double originX;
  final double originY;
  final double originZ;

  final double cellSize;
  final double cellHeight;
  final int columns;
  final int rows;

  /// The lattice column and row of this field's column `(0, 0)`.
  final int offsetX;
  final int offsetZ;

  /// Per column, `cz * columns + cx`, merged and sorted by height.
  final List<List<SolidSpan>> spans;

  bool get isEmpty => columns == 0 || rows == 0;

  /// Rasterises the solid [brushes] and the [ground] into columns of spans,
  /// over [window] of [lattice] — all of it unless told otherwise.
  ///
  /// [areaOf] names a brush's walking surface; [groundArea] is the terrain's.
  /// A surface steeper than `config.maxSlope` is solid and not a floor.
  ///
  /// **The lattice is `NavGrid.bake`'s** unless one is given — see
  /// [NavLattice.of]. **A column of a window is the same column of the whole**,
  /// bit for bit: every position is worked out from the lattice's origin and
  /// the column's index in the lattice, never from the window's corner, so a
  /// part baked again agrees with the whole baked once.
  static SpanField rasterise(
    Iterable<Brush> brushes, {
    required NavMeshConfig config,
    Heightfield? ground,
    required int Function(Brush brush) areaOf,
    required int groundArea,
    NavLattice? lattice,
    NavWindow? window,
  }) {
    final solid = <Brush>[
      for (final brush in brushes)
        if (brush.solid) brush,
    ];
    final cs = config.cellSize;
    final ch = config.cellHeight;
    final grid =
        lattice ?? NavLattice.of(solid, config: config, ground: ground);
    final samples = ground?.copyOfSamples();
    final groundLow = samples == null || samples.isEmpty
        ? null
        : samples.reduce(math.min).toDouble();

    final w =
        window ?? (x0: 0, z0: 0, x1: grid.columns, z1: grid.rows);
    final columns = math.max(0, w.x1 - w.x0);
    final rows = math.max(0, w.z1 - w.z0);
    if (grid.isEmpty || columns == 0 || rows == 0) {
      return SpanField._(
        originX: grid.originX,
        originY: grid.originY,
        originZ: grid.originZ,
        cellSize: cs,
        cellHeight: ch,
        columns: 0,
        rows: 0,
        offsetX: w.x0,
        offsetZ: w.z0,
        spans: const <List<SolidSpan>>[],
      );
    }

    final minX = grid.originX;
    final minY = grid.originY;
    final minZ = grid.originZ;
    final raw = List<List<SolidSpan>>.generate(
      columns * rows,
      (_) => <SolidSpan>[],
    );

    int floorVoxel(double y) =>
        math.max(0, (((y - minY) / ch) + Tolerance.gridBias).floor());
    int topVoxel(double y) => (((y - minY) / ch) - Tolerance.gridBias).ceil();

    // Compared as a ratio rather than as an angle, so the only transcendental
    // in the whole bake is this one portable tangent.
    final steepest = Portable.tan(config.maxSlope);

    for (final brush in solid) {
      final lo = brush.min;
      final hi = brush.max;
      final ramp = brush.ramp;
      final rampWalkable =
          ramp == null ||
          brush.size.y <=
              steepest * (ramp.x != 0.0 ? brush.size.x : brush.size.z);
      final area = areaOf(brush);

      // Every column the brush overlaps by more than a hair, exactly as
      // `NavGrid` buckets them; then only those in the window.
      final x0 = math.max(
        w.x0,
        _clamp(((lo.x - minX) / cs + Tolerance.gridBias).floor(), grid.columns),
      );
      final x1 = math.min(
        w.x1 - 1,
        _clamp(((hi.x - minX) / cs - Tolerance.gridBias).floor(), grid.columns),
      );
      final z0 = math.max(
        w.z0,
        _clamp(((lo.z - minZ) / cs + Tolerance.gridBias).floor(), grid.rows),
      );
      final z1 = math.min(
        w.z1 - 1,
        _clamp(((hi.z - minZ) / cs - Tolerance.gridBias).floor(), grid.rows),
      );

      for (var cz = z0; cz <= z1; cz++) {
        final pz = minZ + (cz + 0.5) * cs;
        for (var cx = x0; cx <= x1; cx++) {
          final px = minX + (cx + 0.5) * cs;
          final centred = px >= lo.x && px < hi.x && pz >= lo.z && pz < hi.z;
          final top = ramp == null
              ? hi.y
              : _rampHeight(brush, ramp.x, ramp.z, px, pz);
          final bottom = floorVoxel(lo.y);
          raw[(cz - w.z0) * columns + (cx - w.x0)].add(
            SolidSpan(
              bottom,
              math.max(bottom, topVoxel(top)),
              centred && rampWalkable ? area : nullArea,
            ),
          );
        }
      }
    }

    if (ground != null) {
      final bottom = floorVoxel(groundLow!);
      for (var cz = math.max(0, w.z0); cz < math.min(grid.rows, w.z1); cz++) {
        final pz = minZ + (cz + 0.5) * cs;
        for (
          var cx = math.max(0, w.x0);
          cx < math.min(grid.columns, w.x1);
          cx++
        ) {
          final px = minX + (cx + 0.5) * cs;
          // Off the field is not ground, for `bakeHeightfield`'s reason: the
          // field answers beyond its edge with the edge's height, and a floor
          // laid on that answer is a floor that is not there.
          if (!ground.contains(px, pz)) continue;
          raw[(cz - w.z0) * columns + (cx - w.x0)].add(
            SolidSpan(
              bottom,
              math.max(bottom, topVoxel(ground.heightAt(px, pz))),
              ground.slopeAt(px, pz) <= config.maxSlope ? groundArea : nullArea,
            ),
          );
        }
      }
    }

    return SpanField._(
      originX: minX,
      originY: minY,
      originZ: minZ,
      cellSize: cs,
      cellHeight: ch,
      columns: columns,
      rows: rows,
      offsetX: w.x0,
      offsetZ: w.z0,
      spans: <List<SolidSpan>>[for (final column in raw) _merged(column)],
    );
  }

  /// Joins spans that overlap or touch.
  ///
  /// **Sorted before it is merged, so the order brushes are listed in cannot
  /// matter.** Merging in arrival order makes the area of a shared top
  /// depend on which brush came first; merging in sorted order makes it the
  /// largest area among the spans that reach the top, whoever listed them.
  static List<SolidSpan> _merged(List<SolidSpan> column) {
    if (column.length < 2) return column;
    column.sort(
      (a, b) => a.min != b.min
          ? a.min - b.min
          : (a.max != b.max ? a.max - b.max : a.area - b.area),
    );
    final out = <SolidSpan>[];
    var current = column.first;
    for (final next in column.skip(1)) {
      if (next.min > current.max) {
        out.add(current);
        current = next;
      } else if (next.max > current.max) {
        current = SolidSpan(current.min, next.max, next.area);
      } else if (next.max == current.max) {
        current = SolidSpan(
          current.min,
          current.max,
          math.max(current.area, next.area),
        );
      }
    }
    out.add(current);
    return out;
  }

  /// The ramp's surface over `(x, z)`, held inside its footprint so that a
  /// column the ramp only clips is filled to the nearest height it has.
  static double _rampHeight(
    Brush brush,
    double uphillX,
    double uphillZ,
    double x,
    double z,
  ) {
    final lo = brush.min;
    final size = brush.size;
    final along = uphillX != 0.0 ? (x - lo.x) / size.x : (z - lo.z) / size.z;
    final t = (uphillX + uphillZ > 0.0 ? along : 1.0 - along).clamp(0.0, 1.0);
    return lo.y + size.y * t;
  }

  /// A top that is not a floor becomes one when it is a step up from a floor
  /// in the same column.
  ///
  /// What it is for is a ledge the slope test refused and the agent can still
  /// step onto — a kerb on a hillside, the lip of a steep ramp. Decided from
  /// what each span was before this pass, so a stack of such tops does not
  /// climb itself one step at a time.
  void filterLowHangingObstacles(int climb) {
    for (final column in spans) {
      var belowWalkable = false;
      var belowArea = nullArea;
      var belowTop = 0;
      for (final span in column) {
        final walkable = span.area != nullArea;
        if (!walkable &&
            belowWalkable &&
            (span.max - belowTop).abs() <= climb) {
          span.area = belowArea;
        }
        belowWalkable = walkable;
        belowArea = span.area;
        belowTop = span.max;
      }
    }
  }

  /// A floor with less room above it than [height] is not a floor.
  void filterLowHeight(int height) {
    for (final column in spans) {
      for (var i = 0; i < column.length; i++) {
        final ceiling = i + 1 < column.length ? column[i + 1].min : sky;
        if (ceiling - column[i].max < height) column[i].area = nullArea;
      }
    }
  }

  /// The height of open sky, in voxels: more room than any agent asks for.
  static const int sky = 0x3fffffff;

  static int _clamp(int value, int count) =>
      value < 0 ? 0 : (value >= count ? count - 1 : value);
}
