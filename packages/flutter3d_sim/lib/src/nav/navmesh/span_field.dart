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
    required this.spans,
  });

  /// The world position of voxel `(0, 0, 0)`'s lowest corner.
  final double originX;
  final double originY;
  final double originZ;

  final double cellSize;
  final double cellHeight;
  final int columns;
  final int rows;

  /// Per column, `cz * columns + cx`, merged and sorted by height.
  final List<List<SolidSpan>> spans;

  bool get isEmpty => columns == 0 || rows == 0;

  /// Rasterises the solid [brushes] and the [ground] into columns of spans.
  ///
  /// [areaOf] names a brush's walking surface; [groundArea] is the terrain's.
  /// A surface steeper than `config.maxSlope` is solid and not a floor.
  ///
  /// **The lattice is `NavGrid.bake`'s**: its corner at the least x and z any
  /// solid brush reaches, its count the extent over the cell size rounded up.
  /// Terrain widens it to cover the field.
  static SpanField rasterise(
    Iterable<Brush> brushes, {
    required NavMeshConfig config,
    Heightfield? ground,
    required int Function(Brush brush) areaOf,
    required int groundArea,
  }) {
    final solid = <Brush>[
      for (final brush in brushes)
        if (brush.solid) brush,
    ];
    final cs = config.cellSize;
    final ch = config.cellHeight;
    final samples = ground?.copyOfSamples();
    final groundLow = samples == null || samples.isEmpty
        ? null
        : samples.reduce(math.min).toDouble();

    if (solid.isEmpty && ground == null) {
      return SpanField._(
        originX: 0.0,
        originY: 0.0,
        originZ: 0.0,
        cellSize: cs,
        cellHeight: ch,
        columns: 0,
        rows: 0,
        spans: const <List<SolidSpan>>[],
      );
    }

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

    final columns = math.max(1, ((maxX - minX) / cs).ceil());
    final rows = math.max(1, ((maxZ - minZ) / cs).ceil());
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
      // `NavGrid` buckets them.
      final x0 = _clamp(
        ((lo.x - minX) / cs + Tolerance.gridBias).floor(),
        columns,
      );
      final x1 = _clamp(
        ((hi.x - minX) / cs - Tolerance.gridBias).floor(),
        columns,
      );
      final z0 = _clamp(
        ((lo.z - minZ) / cs + Tolerance.gridBias).floor(),
        rows,
      );
      final z1 = _clamp(
        ((hi.z - minZ) / cs - Tolerance.gridBias).floor(),
        rows,
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
          raw[cz * columns + cx].add(
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
      for (var cz = 0; cz < rows; cz++) {
        final pz = minZ + (cz + 0.5) * cs;
        for (var cx = 0; cx < columns; cx++) {
          final px = minX + (cx + 0.5) * cs;
          // Off the field is not ground, for `bakeHeightfield`'s reason: the
          // field answers beyond its edge with the edge's height, and a floor
          // laid on that answer is a floor that is not there.
          if (!ground.contains(px, pz)) continue;
          raw[cz * columns + cx].add(
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
