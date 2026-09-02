/// The level as the player has seen it.
///
///     dart test test/automap_test.dart
///
/// Three rooms: a doorway between A and B, a wall between B and C. A player
/// in A reveals A; walking through the doorway reveals B; C stays dark until
/// somebody stands in it, because the reveal walks and does not radiate. And
/// what was seen survives a snapshot.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Brush _box(double x, double y, double z, double sx, double sy, double sz) =>
    Brush(centre: Vector3(x, y, z), size: Vector3(sx, sy, sz));

/// Rooms A (x 0..8), B (x 10..18) and C (x 20..28), 8 m deep and 4 m high.
/// A–B share a wall with a 2 m doorway at z 3..5; B–C's wall is solid.
Level _rooms() => Level(
  brushes: <Brush>[
    _box(14.0, -0.5, 4.0, 30.0, 1.0, 10.0),
    _box(14.0, 4.5, 4.0, 30.0, 1.0, 10.0),
    _box(14.0, 2.0, -0.5, 30.0, 4.0, 1.0),
    _box(14.0, 2.0, 8.5, 30.0, 4.0, 1.0),
    _box(-0.5, 2.0, 4.0, 1.0, 4.0, 8.0),
    _box(28.5, 2.0, 4.0, 1.0, 4.0, 8.0),
    _box(9.0, 2.0, 1.5, 2.0, 4.0, 3.0),
    _box(9.0, 2.0, 6.5, 2.0, 4.0, 3.0),
    _box(19.0, 2.0, 4.0, 2.0, 4.0, 8.0),
  ],
);

NavGrid _grid() => NavGrid.bake(_rooms().brushes, cellSize: 0.5);

int _cell(NavGrid grid, double x, double z) => grid.cellAtPoint(x, z);

void main() {
  test('a player in A sees A and not B or C', () {
    final grid = _grid();
    final map = Automap(grid, revealRadius: 5.0);

    map.reveal(Vector3(4.0, 0.1, 4.0));

    expect(map.isRevealed(_cell(grid, 2.0, 2.0)), isTrue, reason: 'in A');
    expect(map.isRevealed(_cell(grid, 6.0, 6.0)), isTrue, reason: 'in A');
    expect(
      map.isRevealed(_cell(grid, 14.0, 4.0)),
      isFalse,
      reason: 'B is past the doorway and the radius',
    );
    expect(map.isRevealed(_cell(grid, 24.0, 4.0)), isFalse, reason: 'C');
    expect(map.revealedCount, greaterThan(100));
  });

  test('the walls around what was seen are seen too', () {
    final grid = _grid();
    final map = Automap(grid, revealRadius: 5.0)
      ..reveal(Vector3(4.0, 0.1, 4.0));

    // The end wall at x -1..0 beside room A.
    final wall = _cell(grid, -0.5, 4.0);
    expect(map.isFloor(wall), isFalse);
    expect(map.isRevealed(wall), isTrue);
    expect(map.isWall(wall), isTrue);
    // The B–C wall is nowhere near.
    expect(map.isWall(_cell(grid, 19.0, 4.0)), isFalse);
  });

  test('the reveal walks through the doorway and not through the wall', () {
    final grid = _grid();
    final map = Automap(grid, revealRadius: 12.0);

    // Standing at the doorway: B is within reach through it, C is within
    // twelve metres of walking too — but only if the wall let the walk
    // through, which it does not.
    map.reveal(Vector3(9.0, 0.1, 4.0));

    expect(map.isRevealed(_cell(grid, 14.0, 4.0)), isTrue, reason: 'B');
    expect(map.isRevealed(_cell(grid, 17.0, 2.0)), isTrue, reason: 'B far');
    expect(map.isRevealed(_cell(grid, 21.0, 4.0)), isFalse, reason: 'C');
  });

  test('standing still reveals nothing new, and moving does', () {
    final grid = _grid();
    final map = Automap(grid, revealRadius: 3.0)
      ..reveal(Vector3(2.0, 0.1, 2.0));
    final before = map.revealedCount;

    map.reveal(Vector3(2.1, 0.1, 2.1));
    expect(map.revealedCount, before, reason: 'the same cell');

    map.reveal(Vector3(6.0, 0.1, 6.0));
    expect(map.revealedCount, greaterThan(before));
  });

  test('a map pickup shows everything the player could walk to', () {
    final grid = _grid();
    final map = Automap(grid, revealRadius: 1.0)
      ..revealAll(Vector3(4.0, 0.1, 4.0));

    expect(map.everythingRevealed, isTrue);
    expect(map.isRevealed(_cell(grid, 17.0, 6.0)), isTrue, reason: 'all of B');
    expect(
      map.isWall(_cell(grid, 18.25, 4.0)),
      isTrue,
      reason: 'the face of the B–C wall; a wall is one cell thick on the map',
    );
    // C is sealed: no door leads there, so no map shows it. A pickup reveals
    // the level as it can be walked, and the roof and the sealed rooms are
    // not part of that — which is also what keeps the roof off the map.
    expect(map.isRevealed(_cell(grid, 24.0, 4.0)), isFalse);
  });

  test('what was seen survives a snapshot', () {
    final grid = _grid();
    final map = Automap(grid, revealRadius: 5.0)
      ..reveal(Vector3(4.0, 0.1, 4.0));
    final seen = map.revealedCount;

    final restored = Automap(grid)..restore(map.save());

    expect(restored.revealedCount, seen);
    expect(restored.isRevealed(_cell(grid, 2.0, 2.0)), isTrue);
    expect(restored.isRevealed(_cell(grid, 24.0, 4.0)), isFalse);
  });

  test('a snapshot from another grid is not applied', () {
    final grid = _grid();
    final map = Automap(grid)..reveal(Vector3(4.0, 0.1, 4.0));
    final other = Automap(NavGrid.bake(_rooms().brushes, cellSize: 1.0))
      ..reveal(Vector3(4.0, 0.1, 4.0));

    final restored = Automap(grid)..restore(other.save());

    expect(restored.revealedCount, 0, reason: 'wrong length, ignored');
    expect(map.revealedCount, greaterThan(0));
  });
}
