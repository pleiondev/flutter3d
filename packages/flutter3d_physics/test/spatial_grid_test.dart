/// The broadphase, on its own.
///
/// It has been exercised only through `CollisionWorld` until now, which tests
/// what the world does with the answers rather than what the grid says. The
/// one subtle thing in the file is the stamp deduplication, and its own doc
/// explains why it matters: *"callers that accumulate — collecting overlaps,
/// summing depenetration — very much do"* care about being told twice.
///
/// That is exactly the kind of defect a higher-level test hides: a world that
/// depenetrates against a doubled collider pushes twice as far, which reads as
/// a bouncy wall rather than as a broadphase reporting a duplicate.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A box, as the grid wants it.
Aabb3 _box(double minX, double minZ, double maxX, double maxZ) =>
    Aabb3.minMax(Vector3(minX, 0.0, minZ), Vector3(maxX, 1.0, maxZ));

/// Everything the grid reports for a query over [min]..[max].
List<int> _inBox(SpatialGrid grid, double minX, double minZ, double maxX,
    double maxZ) {
  final seen = <int>[];
  grid.forEachInBox(
    Vector3(minX, 0.0, minZ),
    Vector3(maxX, 1.0, maxZ),
    seen.add,
  );
  return seen;
}

void main() {
  test('something spanning four cells is reported once, not four times', () {
    // The stamp's whole job. At a cell size of 4 this box covers the corner
    // where four cells meet, so a walk with no deduplication visits it once
    // per cell.
    //
    // Mutation: delete the `_stamp[handle] = _query` write. This fails with
    // four entries instead of one.
    final grid = SpatialGrid(cellSize: 4.0);
    grid.insert(7, _box(-1.0, -1.0, 1.0, 1.0));

    expect(_inBox(grid, -2.0, -2.0, 2.0, 2.0), <int>[7]);
  });

  test('and again on the next query, which is what the counter is for', () {
    // A stamp scheme that never advanced its counter would report the handle
    // the first time and silently swallow it for the rest of the program.
    //
    // Mutation: stop incrementing `_query` in `forEachInBox`. The first
    // expectation passes and this one fails, which is the pair that makes the
    // test mean something.
    final grid = SpatialGrid(cellSize: 4.0);
    grid.insert(7, _box(-1.0, -1.0, 1.0, 1.0));

    expect(_inBox(grid, -2.0, -2.0, 2.0, 2.0), <int>[7]);
    expect(_inBox(grid, -2.0, -2.0, 2.0, 2.0), <int>[7]);
    expect(_inBox(grid, -2.0, -2.0, 2.0, 2.0), <int>[7]);
  });

  test('a query reports what overlaps it and nothing else', () {
    final grid = SpatialGrid(cellSize: 2.0)
      ..insert(1, _box(0.0, 0.0, 1.0, 1.0))
      ..insert(2, _box(20.0, 20.0, 21.0, 21.0));

    expect(_inBox(grid, -0.5, -0.5, 1.5, 1.5), <int>[1]);
    expect(_inBox(grid, 19.5, 19.5, 21.5, 21.5), <int>[2]);
    expect(_inBox(grid, 100.0, 100.0, 101.0, 101.0), isEmpty);
  });

  test('a handle above the stamp array does not walk off the end', () {
    // Handles are indices into a growable stamp list, and nothing stops a
    // caller from inserting handle 500 first. Growing on demand is the whole
    // reason this is not a fixed array.
    final grid = SpatialGrid(cellSize: 2.0);
    grid.insert(500, _box(0.0, 0.0, 1.0, 1.0));

    expect(_inBox(grid, -1.0, -1.0, 2.0, 2.0), <int>[500]);
  });

  test('clearing keeps the buckets and forgets what was in them', () {
    // Rebuilt every step for the moving half of the world, so the allocation
    // behaviour is the point: `cellCount` stays up while the contents go.
    final grid = SpatialGrid(cellSize: 2.0)
      ..insert(1, _box(0.0, 0.0, 1.0, 1.0));
    final cells = grid.cellCount;
    expect(cells, greaterThan(0));

    grid.clearEntries();

    expect(_inBox(grid, -1.0, -1.0, 2.0, 2.0), isEmpty);
    expect(grid.cellCount, cells,
        reason: 'the buckets were dropped rather than emptied, so a step that '
            'rebuilds the world allocates a map entry per cell every frame');
  });

  test('a ray reports each crossed occupant once', () {
    // The same deduplication down the other path: a long collider lying along
    // the ray occupies every cell the walk enters.
    final grid = SpatialGrid(cellSize: 1.0);
    grid.insert(3, _box(0.0, -0.5, 10.0, 0.5));

    final seen = <int>[];
    grid.forEachAlongRay(
      Vector3(-1.0, 0.5, 0.0),
      Vector3(1.0, 0.0, 0.0),
      20.0,
      seen.add,
    );

    expect(seen, <int>[3]);
  });
}
