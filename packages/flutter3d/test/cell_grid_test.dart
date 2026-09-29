/// A grid of cells there or not, worn away, and drawn as blocks.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a shield from its picture, worn away a shot at a time', () {
    final shield = CellGrid.fromMask(<String>[
      ' #### ',
      '######',
      '##  ##',
    ], cell: 0.5);
    expect(shield.columns, 6);
    expect(shield.rows, 3);
    expect(shield.count, 14);
    expect(shield.isAlive(0, 0), isFalse);
    expect(shield.isAlive(1, 0), isTrue);

    // A shot at the middle of the top-left block takes it and its
    // neighbours within half a metre.
    final gone = shield.clearAround(0.75, 0.25, 0.5);
    expect(gone, greaterThan(0));
    expect(shield.isAlive(1, 0), isFalse);
    expect(shield.count, 14 - gone);
  });

  test('its blocks are one mesh of the cells still there, or none', () {
    final grid = CellGrid.fromMask(<String>['##', '#.']);
    final three = grid.mesh(place: (x, y) => Vector3(x, 0.0, y))!;
    final one = CuboidShape(size: Vector3.all(1.0)).build();
    expect(three.indices.length, one.indices.length * 3);

    grid
      ..clear(0, 0)
      ..clear(1, 0)
      ..clear(0, 1);
    expect(grid.mesh(place: (x, y) => Vector3(x, 0.0, y)), isNull);
  });
}
