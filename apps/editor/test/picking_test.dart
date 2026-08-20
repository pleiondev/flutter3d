/// Pointing at a brush.
///
///     flutter test test/picking_test.dart
library;

import 'dart:math' as math;

import 'package:editor/src/picking.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Brush _brush(Vector3 at, {Vector3? size, bool solid = true}) => Brush(
      centre: at,
      size: size ?? Vector3(2.0, 2.0, 2.0),
      solid: solid,
    );

void main() {
  test('the ray finds what is in front of it', () {
    final brushes = <Brush>[_brush(Vector3(0.0, 0.0, -10.0))];

    expect(
      Picking.brushAt(brushes, Vector3.zero(), Vector3(0.0, 0.0, -1.0)),
      0,
    );
  });

  test('and nothing when it points the other way', () {
    final brushes = <Brush>[_brush(Vector3(0.0, 0.0, -10.0))];

    expect(
      Picking.brushAt(brushes, Vector3.zero(), Vector3(0.0, 0.0, 1.0)),
      isNull,
    );
  });

  test('and the nearer of two, not whichever is first in the list', () {
    final brushes = <Brush>[
      _brush(Vector3(0.0, 0.0, -30.0)),
      _brush(Vector3(0.0, 0.0, -10.0)),
    ];

    expect(
      Picking.brushAt(brushes, Vector3.zero(), Vector3(0.0, 0.0, -1.0)),
      1,
    );
  });

  test('and a brush that stops nothing is still pointed at', () {
    // **The reason this does not ask the collision world.** Every brush is a
    // box and the physics can already sweep against those — but a brush with
    // `solid: false` never reaches the collision world at all, and those are
    // the mouldings, the painted alcoves, the lip of a step. Exactly the
    // decoration somebody opens an editor to move, and it would have been the
    // one thing they could not click on.
    final brushes = <Brush>[_brush(Vector3(0.0, 0.0, -10.0), solid: false)];

    expect(
      Picking.brushAt(brushes, Vector3.zero(), Vector3(0.0, 0.0, -1.0)),
      0,
    );
  });

  test('and a ray parallel to a face misses rather than hitting', () {
    // The division by zero that a slab test has to answer for. A ray running
    // straight down a wall is either inside it for its whole length or never
    // touches it.
    final brushes = <Brush>[_brush(Vector3(0.0, 0.0, 0.0))];

    expect(
      Picking.brushAt(brushes, Vector3(4.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0)),
      isNull,
    );
    expect(
      Picking.brushAt(brushes, Vector3(0.5, 0.0, 20.0), Vector3(0.0, 0.0, -1.0)),
      0,
    );
  });

  test('and standing inside one selects it', () {
    final brushes = <Brush>[_brush(Vector3.zero(), size: Vector3(8.0, 8.0, 8.0))];

    expect(
      Picking.brushAt(brushes, Vector3.zero(), Vector3(1.0, 0.0, 0.0)),
      0,
    );
  });

  group('the direction a click points', () {
    final size = Vector2(800.0, 600.0);
    final forward = Vector3(0.0, 0.0, -1.0);
    final right = Vector3(1.0, 0.0, 0.0);
    final up = Vector3(0.0, 1.0, 0.0);

    Vector3 through(double x, double y) => Picking.through(
          Vector2(x, y),
          size: size,
          forward: forward,
          right: right,
          up: up,
          fovY: math.pi / 4,
        );

    test('is straight ahead in the middle of the window', () {
      final ray = through(400.0, 300.0);

      expect(ray.x, closeTo(0.0, 1e-9));
      expect(ray.y, closeTo(0.0, 1e-9));
      expect(ray.z, closeTo(-1.0, 1e-9));
    });

    test('and points up when the click is up', () {
      // **The sign nobody gets right first time.** Screen coordinates have y
      // downwards and the world has it upwards; a picker that misses this
      // selects the brush above whatever was clicked and only above, which
      // looks like an aim problem rather than a flipped axis.
      expect(through(400.0, 100.0).y, greaterThan(0.0));
      expect(through(400.0, 500.0).y, lessThan(0.0));
    });

    test('and right when the click is right', () {
      expect(through(700.0, 300.0).x, greaterThan(0.0));
      expect(through(100.0, 300.0).x, lessThan(0.0));
    });

    test('and it is a unit vector, so a hit distance is in metres', () {
      expect(through(700.0, 100.0).length, closeTo(1.0, 1e-6));
    });

    test('and a wide window reaches further sideways than up', () {
      // The aspect ratio, which is the other easy one to drop: a picker that
      // ignored it would be accurate down the middle of the window and wrong at
      // the edges, on wide monitors only.
      final wide = Picking.through(
        Vector2(800.0, 300.0),
        size: Vector2(800.0, 300.0),
        forward: forward,
        right: right,
        up: up,
        fovY: math.pi / 4,
      );
      final tall = Picking.through(
        Vector2(300.0, 300.0),
        size: Vector2(300.0, 800.0),
        forward: forward,
        right: right,
        up: up,
        fovY: math.pi / 4,
      );

      expect(wide.x, greaterThan(tall.x));
    });
  });
}
