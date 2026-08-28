import '../math/tolerances.dart';
import 'level.dart';

/// Which brushes sit near a point, without walking all of them.
///
/// An implementation detail of [BrushGeometry]'s hidden-face culling, kept in
/// its own file for the same reason [SurfaceBuilder] is: it is a data
/// structure the generator leans on, not part of what a brush or a level is.
final class BrushIndex {
  BrushIndex(this.level, this.cellSize) {
    for (var i = 0; i < level.brushes.length; i++) {
      final brush = level.brushes[i];
      if (!brush.solid) continue;
      // **A ramp hides nothing.** Its box is half empty — that is what a ramp
      // is — so treating it as solid here would cull a neighbour's face that
      // stands in the air above the slope, and a hole in a wall is far worse
      // than a triangle nobody sees.
      if (brush.isRamp) continue;
      final min = brush.min;
      final max = brush.max;
      for (
        var x = (min.x / cellSize).floor();
        x <= (max.x / cellSize).floor();
        x++
      ) {
        for (
          var z = (min.z / cellSize).floor();
          z <= (max.z / cellSize).floor();
          z++
        ) {
          (_cells[(x << 32) ^ (z & 0xFFFFFFFF)] ??= <int>[]).add(i);
        }
      }
    }
  }

  final Level level;
  final double cellSize;
  final Map<int, List<int>> _cells = <int, List<int>>{};

  /// Whether any solid brush other than [except] strictly contains the point.
  ///
  /// Strictly: a point exactly on another brush's surface does not count, so
  /// two brushes that merely share a face both keep their faces.
  bool containsPoint(double x, double y, double z, Brush except) {
    const epsilon = Tolerance.sameSurface;
    final bucket =
        _cells[((x / cellSize).floor() << 32) ^
            ((z / cellSize).floor() & 0xFFFFFFFF)];
    if (bucket == null) return false;

    for (final i in bucket) {
      final other = level.brushes[i];
      if (identical(other, except)) continue;
      final min = other.min;
      final max = other.max;
      if (x > min.x + epsilon &&
          x < max.x - epsilon &&
          y > min.y + epsilon &&
          y < max.y - epsilon &&
          z > min.z + epsilon &&
          z < max.z - epsilon) {
        return true;
      }
    }
    return false;
  }
}
