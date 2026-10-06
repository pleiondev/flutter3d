/// The flow field's grid baked again where a wall was broken: the grid a
/// whole bake of the broken level makes, cell for cell.
///
///     flutter test test/nav_grid_rebake_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void _same(NavGrid a, NavGrid b) {
  expect(
    (a.originX, a.originZ, a.columns, a.rows),
    (b.originX, b.originZ, b.columns, b.rows),
  );
  for (var i = 0; i < a.columns * a.rows; i++) {
    expect(
      (a.floorAt(i), a.headroomAt(i), a.clearanceAt(i)),
      (b.floorAt(i), b.headroomAt(i), b.clearanceAt(i)),
      reason: 'cell $i',
    );
  }
}

/// [level] broken by [box], its grid rebaked over the box and baked whole.
(NavGrid, NavGrid, NavGrid) _broken(Level level, Aabb3 box) {
  final world = CollisionWorld();
  level.addTo(world);
  final breaches = Breaches(level, world, breakable: (Brush _) => true);
  final before = NavGrid.bake(expandRecipes(level).brushes, cellSize: 0.25);
  breaches.hole(box);
  final brushes = expandRecipes(
    Level(name: level.name, brushes: breaches.brushes, recipes: level.recipes),
  ).brushes;
  final rebaked = before.rebake(
    brushes,
    minX: box.min.x,
    minZ: box.min.z,
    maxX: box.max.x,
    maxZ: box.max.z,
  );
  return (before, rebaked, NavGrid.bake(brushes, cellSize: 0.25));
}

void main() {
  test(
    'a hole through a wall across a room: the whole bake, cell for cell',
    () {
      final level = Level(
        name: 'walled',
        brushes: <Brush>[
          Brush(
            centre: Vector3(0.0, -0.5, 0.0),
            size: Vector3(20.0, 1.0, 20.0),
          ),
          Brush(centre: Vector3(0.0, 1.5, 0.0), size: Vector3(1.0, 3.0, 20.0)),
        ],
      );
      final hole = Aabb3.minMax(
        Vector3(-1.0, 0.0, -1.0),
        Vector3(1.0, 2.2, 1.0),
      );
      final (before, rebaked, whole) = _broken(level, hole);
      _same(rebaked, whole);
      // And it changed something: where the wall's top was, three metres
      // up, is the floor of a doorway now. Mutation: leaving the columns as
      // they were baked.
      final doorway = whole.cellAtPoint(0.0, 0.0);
      expect(before.floorAt(doorway), closeTo(3.0, 1e-6));
      expect(rebaked.floorAt(doorway), closeTo(0.0, 1e-6));
    },
  );

  for (final name in <String>['crypt', 'deep']) {
    test('the $name broken where it breaks: the whole bake', () {
      final level = Level.fromJson(
        jsonDecode(
              File(
                '../../apps/flutter3d_demo_dungeon/assets/levels/$name.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>,
      );
      // A box through the middle of the level, wherever that is.
      final grid = NavGrid.bake(expandRecipes(level).brushes, cellSize: 0.25);
      final cx = grid.originX + grid.columns * 0.25 / 2;
      final cz = grid.originZ + grid.rows * 0.25 / 2;
      final hole = Aabb3.minMax(
        Vector3(cx - 1.5, 0.0, cz - 1.5),
        Vector3(cx + 1.5, 2.5, cz + 1.5),
      );
      final (_, rebaked, whole) = _broken(level, hole);
      _same(rebaked, whole);
    });
  }
}
