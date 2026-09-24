/// The six-way baker — `N6`: six pictures of one puff, each lit from one side.
library;

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:test/test.dart';

/// A ball of even density, half the cube across, still over time.
double _ball(double x, double y, double z, double t) =>
    x * x + y * y + z * z < 0.25 ? 1.0 : 0.0;

void main() {
  const cell = 24;

  int channel(List<int> bytes, SixWaySheet sheet, int x, int y, int c) =>
      bytes[(y * sheet.width + x) * 4 + c];

  test('a ball is opaque in the middle and empty at the corners', () {
    final sheet = bakeSixWay(density: _ball, frames: 1, columns: 1, cell: cell);
    // Not quite 255: the ball is six units of optical depth through, and
    // e^-6 of the background still shows.
    expect(channel(sheet.positive, sheet, cell ~/ 2, cell ~/ 2, 3), 254);
    expect(channel(sheet.positive, sheet, 0, 0, 3), 0);
  });

  test('each side of a ball is lit by the light on that side', () {
    final sheet = bakeSixWay(density: _ball, frames: 1, columns: 1, cell: cell);
    const middle = cell ~/ 2;
    // Just inside the ball's rim on the right, and on the left.
    const rightRim = middle + 5;
    const leftRim = middle - 6;
    final right = channel(sheet.positive, sheet, rightRim, middle, 0);
    final leftAtRight = channel(sheet.negative, sheet, rightRim, middle, 0);
    final left = channel(sheet.negative, sheet, leftRim, middle, 0);
    final rightAtLeft = channel(sheet.positive, sheet, leftRim, middle, 0);
    // Mutation: sweep the right-hand depth from the low side. The rim that
    // faces the light goes dark and the far one lights up.
    expect(right, greaterThan(leftAtRight + 60));
    expect(left, greaterThan(rightAtLeft + 60));

    // The top of the ball is up the cell: rows run bottom to top.
    const topRim = middle + 5;
    const bottomRim = middle - 6;
    expect(
      channel(sheet.positive, sheet, middle, topRim, 1),
      greaterThan(channel(sheet.negative, sheet, middle, topRim, 1) + 60),
    );
    expect(
      channel(sheet.negative, sheet, middle, bottomRim, 1),
      greaterThan(channel(sheet.positive, sheet, middle, bottomRim, 1) + 60),
    );

    // Through the middle, a light on the viewer's side lights what is seen
    // and one behind is taken out by the whole ball. About half, not all, for
    // the front: its light is dimmed going in as the view is coming out.
    final front = channel(sheet.negative, sheet, middle, middle, 2);
    final back = channel(sheet.positive, sheet, middle, middle, 2);
    expect(front, greaterThan(110));
    expect(back, lessThan(20));
  });

  test('a cell starts at its bottom row', () {
    // Density only in the upper half of the cube.
    final sheet = bakeSixWay(
      density: (x, y, z, t) => y > 0.0 && x * x + z * z < 0.25 ? 1.0 : 0.0,
      frames: 1,
      columns: 1,
      cell: cell,
    );
    // Mutation: write `cell - 1 - y`. The column's coverage moves to the
    // first rows.
    expect(channel(sheet.positive, sheet, cell ~/ 2, 2, 3), 0);
    expect(
      channel(sheet.positive, sheet, cell ~/ 2, cell - 3, 3),
      greaterThan(200),
    );
  });

  test('frames go in reading order, and the rows follow the count', () {
    // A ball that is there only in the last of five frames.
    final sheet = bakeSixWay(
      density: (x, y, z, t) => t == 1.0 ? _ball(x, y, z, t) : 0.0,
      frames: 5,
      columns: 4,
      cell: 8,
    );
    expect(sheet.rows, 2);
    expect(sheet.width, 32);
    expect(sheet.height, 16);
    expect(channel(sheet.positive, sheet, 4, 4, 3), 0);
    // The fifth frame is the first cell of the second row.
    expect(channel(sheet.positive, sheet, 4, 12, 3), greaterThan(200));
  });

  test('emission is carried, unpremultiplied, in the negative alpha', () {
    final sheet = bakeSixWay(
      density: _ball,
      emission: (x, y, z, t) => 0.5,
      frames: 1,
      columns: 1,
      cell: cell,
    );
    expect(
      channel(sheet.negative, sheet, cell ~/ 2, cell ~/ 2, 3),
      inInclusiveRange(127, 128),
    );
  });

  test('the engine smoke bakes the same bytes from the same seed', () {
    SixWaySheet bake(int seed) =>
        bakeSixWay(density: smokePuff(seed: seed), frames: 4, cell: 12);
    expect(bake(3).positive, bake(3).positive);
    expect(bake(3).positive, isNot(bake(4).positive));
    // It is a puff: something is covered in every frame.
    final sheet = bake(3);
    for (var frame = 0; frame < 4; frame++) {
      final x = frame * 12 + 6;
      expect(channel(sheet.positive, sheet, x, 6, 3), greaterThan(0));
    }
  });
}
