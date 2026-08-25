import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

/// A uniform grid over the XZ plane, holding integer handles.
///
/// ## Why a grid
///
/// A corridor level spreads thousands of brushes thinly and evenly, which is
/// the case a uniform grid handles best and a tree handles worst: no
/// rebalancing, no traversal, and a query touches a fixed handful of cells
/// whatever the level's size. It is also the case the engine's own BVH measured
/// badly on, and that measurement is in `ARCHITECTURE.md` §2.
///
/// Two dimensions rather than three, because a dungeon is wide and short.
/// Adding Y would multiply the cell count by the number of floors — usually one
/// — while splitting almost nothing.
///
/// ## Why the stamps
///
/// A collider spanning several cells appears in each of them, so a naive walk
/// reports it more than once. Callers that take a minimum do not care, but
/// callers that accumulate — collecting overlaps, summing depenetration — very
/// much do. A monotonically increasing query counter and one stamp per handle
/// makes the deduplication O(1) per visit instead of a set allocated per query.
final class SpatialGrid {
  SpatialGrid({this.cellSize = 4.0});

  /// Side of a cell, in metres. About two corridor widths, so a query for a
  /// player-sized box touches one or two cells.
  final double cellSize;

  /// Cell key to the handles inside it.
  ///
  /// Bucket lists are cleared rather than dropped by [clearEntries], so
  /// rebuilding the dynamic half of the world every step allocates nothing
  /// after the first few frames.
  final Map<int, List<int>> _cells = <int, List<int>>{};

  Int32List _stamp = Int32List(0);
  int _query = 0;

  int get cellCount => _cells.length;

  void insert(int handle, Aabb3 bounds) {
    if (handle >= _stamp.length) _growStamps(handle + 1);

    final x0 = (bounds.min.x / cellSize).floor();
    final x1 = (bounds.max.x / cellSize).floor();
    final z0 = (bounds.min.z / cellSize).floor();
    final z1 = (bounds.max.z / cellSize).floor();

    for (var x = x0; x <= x1; x++) {
      for (var z = z0; z <= z1; z++) {
        (_cells[_key(x, z)] ??= <int>[]).add(handle);
      }
    }
  }

  /// Empties every cell but keeps the lists, for a grid rebuilt each step.
  void clearEntries() {
    for (final bucket in _cells.values) {
      bucket.clear();
    }
  }

  /// Drops everything, cells included.
  void clear() {
    _cells.clear();
    _query = 0;
    // Reset alongside the counter, or a stamp left over from the old grid
    // matches the first query of the new one and a handle goes unvisited.
    _stamp = Int32List(0);
  }

  /// Visits each handle whose cell meets the region, once.
  void forEachInBox(Vector3 min, Vector3 max, void Function(int) visit) {
    if (_cells.isEmpty) return;
    _query++;

    final x0 = (min.x / cellSize).floor();
    final x1 = (max.x / cellSize).floor();
    final z0 = (min.z / cellSize).floor();
    final z1 = (max.z / cellSize).floor();

    for (var x = x0; x <= x1; x++) {
      for (var z = z0; z <= z1; z++) {
        final bucket = _cells[_key(x, z)];
        if (bucket == null) continue;
        for (final handle in bucket) {
          if (_seen(handle)) continue;
          visit(handle);
        }
      }
    }
  }

  /// Visits each handle in a cell the ray passes through, once, near to far.
  ///
  /// A grid walk rather than the ray's bounding box: a shot down a long
  /// corridor has a bounding box covering everything between the two ends,
  /// which for a diagonal shot is most of the level. Stepping cell by cell
  /// touches only what the ray actually crosses, and does it in roughly the
  /// order the ray meets them, so a caller tracking the nearest hit converges
  /// quickly.
  void forEachAlongRay(
    Vector3 origin,
    Vector3 direction,
    double maxDistance,
    void Function(int) visit,
  ) {
    if (_cells.isEmpty) return;
    _query++;

    var cellX = (origin.x / cellSize).floor();
    var cellZ = (origin.z / cellSize).floor();

    final endX = ((origin.x + direction.x * maxDistance) / cellSize).floor();
    final endZ = ((origin.z + direction.z * maxDistance) / cellSize).floor();

    final stepX = direction.x > 0.0 ? 1 : (direction.x < 0.0 ? -1 : 0);
    final stepZ = direction.z > 0.0 ? 1 : (direction.z < 0.0 ? -1 : 0);

    // Distance along the ray to the next cell boundary on each axis, and the
    // distance between successive boundaries.
    var nextX = double.infinity;
    var deltaX = double.infinity;
    if (stepX != 0) {
      final boundary = (cellX + (stepX > 0 ? 1 : 0)) * cellSize;
      nextX = (boundary - origin.x) / direction.x;
      deltaX = cellSize / direction.x.abs();
    }

    var nextZ = double.infinity;
    var deltaZ = double.infinity;
    if (stepZ != 0) {
      final boundary = (cellZ + (stepZ > 0 ? 1 : 0)) * cellSize;
      nextZ = (boundary - origin.z) / direction.z;
      deltaZ = cellSize / direction.z.abs();
    }

    // A vertical ray never leaves its cell, and the loop below would spin
    // forever waiting for a boundary it never reaches.
    final steps = stepX == 0 && stepZ == 0
        ? 1
        : (endX - cellX).abs() + (endZ - cellZ).abs() + 1;

    for (var i = 0; i < steps; i++) {
      final bucket = _cells[_key(cellX, cellZ)];
      if (bucket != null) {
        for (final handle in bucket) {
          if (_seen(handle)) continue;
          visit(handle);
        }
      }

      if (nextX < nextZ) {
        cellX += stepX;
        nextX += deltaX;
      } else {
        cellZ += stepZ;
        nextZ += deltaZ;
      }
    }
  }

  /// True when this handle has already been reported during the current query.
  bool _seen(int handle) {
    if (handle >= _stamp.length) _growStamps(handle + 1);
    if (_stamp[handle] == _query) return true;
    _stamp[handle] = _query;
    return false;
  }

  void _growStamps(int needed) {
    final grown = Int32List(math.max(needed, _stamp.length * 2 + 16));
    grown.setRange(0, _stamp.length, _stamp);
    _stamp = grown;
  }

  /// Packs a cell coordinate into one integer. Dart integers are 64-bit, so two
  /// 32-bit halves fit exactly.
  static int _key(int x, int z) => (x << 32) ^ (z & 0xFFFFFFFF);
}
