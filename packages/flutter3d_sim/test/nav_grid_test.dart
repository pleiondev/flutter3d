/// Which surface of a column the grid decides an agent stands on.
///
///     dart test test/nav_grid_test.dart
///
/// One height per column, and `nav_grid.dart` says which one wins and why:
/// the **lowest**, because a roofed room's ceiling has open sky over its top
/// face and taking the highest would send every monster in the level onto the
/// roof.
///
/// **It took the highest anyway, for any room dug below the origin.** "Nothing
/// chosen yet" was written as `-1.0` and read as `chosen < 0.0`, and −1.0 is a
/// height like any other: a floor at −1.2 answered the question "have you
/// chosen?" with no, so the sweep carried on and settled on the next surface
/// up. In a room with a ceiling that is the top of the roof, and the whole
/// room bakes as a slab eight metres over the player's head with no floor
/// under it at all — a basin nothing walks into and nothing paths out of.
library;

import 'package:flutter3d_sim/src/level/level.dart';
import 'package:flutter3d_sim/src/nav/nav_grid.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a floor under the origin is the floor, not the roof over it', () {
    // A sunken room: twenty metres square, its floor at −1.2 and a ceiling
    // five metres over it. The only two candidate surfaces in any column are
    // the floor and the top of the roof.
    final grid = NavGrid.bake(<Brush>[
      Brush(centre: Vector3(0.0, -1.7, 0.0), size: Vector3(20.0, 1.0, 20.0)),
      Brush(centre: Vector3(0.0, 5.5, 0.0), size: Vector3(20.0, 1.0, 20.0)),
    ]);
    final cell = grid.cellAt(Vector3(0.0, 0.0, 0.0));

    expect(cell, greaterThanOrEqualTo(0), reason: 'the middle is off the grid');
    expect(
      grid.floorAt(cell),
      closeTo(-1.2, 1e-5),
      reason: 'the grid stands on the roof at ${grid.floorAt(cell)}',
    );
    expect(grid.headroomAt(cell), closeTo(6.2, 1e-5));
    expect(grid.isWalkable(cell), isTrue);
  });
}
