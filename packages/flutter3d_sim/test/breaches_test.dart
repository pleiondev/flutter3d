/// Holes in walls, exactly.
///
///     dart test test/breaches_test.dart
///
/// A box minus a box is at most six boxes, and this pins the arithmetic:
/// nothing lost, nothing gained, and a hole through the wall between two
/// rooms is a hole a ray and a sweep both pass through. Then the run's
/// half: the holes go into the snapshot, and restoring replays them onto the
/// level as authored.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Brush _box(double x, double y, double z, double sx, double sy, double sz) =>
    Brush(centre: Vector3(x, y, z), size: Vector3(sx, sy, sz));

double _volume(Iterable<Brush> brushes) =>
    brushes.fold(0.0, (v, b) => v + b.size.x * b.size.y * b.size.z);

/// Rooms A (x 0..8) and B (x 10..18) with a solid wall at x 8..10, floor and
/// ceiling; a third brush of floor only, to be the thing a hole misses.
Level _rooms() => Level(
  brushes: <Brush>[
    _box(9.0, -0.5, 4.0, 20.0, 1.0, 10.0),
    _box(9.0, 4.5, 4.0, 20.0, 1.0, 10.0),
    _box(9.0, 2.0, -0.5, 20.0, 4.0, 1.0),
    _box(9.0, 2.0, 8.5, 20.0, 4.0, 1.0),
    _box(-0.5, 2.0, 4.0, 1.0, 4.0, 8.0),
    _box(18.5, 2.0, 4.0, 1.0, 4.0, 8.0),
    _box(9.0, 2.0, 4.0, 2.0, 4.0, 8.0),
  ],
);

void main() {
  group('subtracting a box', () {
    final wall = _box(0.0, 0.0, 0.0, 2.0, 4.0, 8.0);

    test('that misses leaves the brush alone', () {
      final hole = Aabb3.minMax(Vector3(5.0, 0.0, 0.0), Vector3(6.0, 1.0, 1.0));
      final pieces = subtractBox(wall, hole);
      expect(pieces, hasLength(1));
      expect(identical(pieces.single, wall), isTrue);
    });

    test('that swallows it leaves nothing', () {
      final hole = Aabb3.minMax(
        Vector3(-5.0, -5.0, -5.0),
        Vector3(5.0, 5.0, 5.0),
      );
      expect(subtractBox(wall, hole), isEmpty);
    });

    test('through the middle keeps every cubic metre but the hole', () {
      // A tunnel straight through along X: the pieces are the wall above,
      // below and either side of it, and their volume is the wall's less the
      // tunnel's.
      final hole = Aabb3.minMax(
        Vector3(-2.0, -1.0, -0.8),
        Vector3(2.0, 1.0, 0.8),
      );
      final pieces = subtractBox(wall, hole);

      expect(pieces.length, inInclusiveRange(2, 6));
      expect(_volume(pieces), closeTo(2.0 * 4.0 * 8.0 - 2.0 * 2.0 * 1.6, 1e-4));
      for (final piece in pieces) {
        expect(piece.material, wall.material);
        expect(piece.castsShadow, wall.castsShadow);
      }
    });

    test('at a corner is one cut on each axis', () {
      final hole = Aabb3.minMax(Vector3(0.0, 1.0, 3.0), Vector3(3.0, 3.0, 5.0));
      final pieces = subtractBox(wall, hole);

      expect(_volume(pieces), closeTo(64.0 - 1.0 * 1.0 * 1.0, 1e-4));
    });

    test('never cuts a ramp', () {
      final ramp = Brush(
        centre: Vector3.zero(),
        size: Vector3(2.0, 2.0, 2.0),
        ramp: WedgeUphill.positiveX,
      );
      final hole = Aabb3.minMax(
        Vector3(-1.0, -1.0, -1.0),
        Vector3(1.0, 1.0, 1.0),
      );
      expect(identical(subtractBox(ramp, hole).single, ramp), isTrue);
    });
  });

  group('a breach', () {
    test('opens the wall to a ray and to a body', () {
      final level = _rooms();
      final world = CollisionWorld();
      level.addTo(world);
      world.update();
      final breaches = Breaches(level, world);
      final hit = RayHit();
      final through = Vector3(1.0, 0.0, 0.0);
      expect(
        world.raycast(Vector3(4.0, 1.0, 4.0), through, 10.0, hit),
        isTrue,
        reason: 'the wall is whole',
      );

      // A rocket on the A side of the wall, at chest height, facing -X out
      // of the wall.
      breaches.blast(Vector3(8.0, 1.0, 4.0), Vector3(-1.0, 0.0, 0.0));
      world.update();

      expect(
        world.raycast(Vector3(4.0, 1.0, 4.0), through, 10.0, hit),
        isFalse,
        reason: 'a ray from A reaches B through the hole',
      );
      expect(
        world.raycast(Vector3(4.0, 1.0, 1.0), through, 10.0, hit),
        isTrue,
        reason: 'beside the hole the wall still stands',
      );
      expect(breaches.version, 1);
      expect(breaches.brushes.length, greaterThan(level.brushes.length));
      expect(_volume(breaches.brushes), lessThan(_volume(level.brushes)));
    });

    test('leaves brushes the game calls unbreakable alone', () {
      final level = _rooms();
      final world = CollisionWorld();
      level.addTo(world);
      world.update();
      final breaches = Breaches(level, world, breakable: (_) => false);

      breaches.blast(Vector3(8.0, 1.0, 4.0), Vector3(-1.0, 0.0, 0.0));

      expect(breaches.brushes, level.brushes);
      expect(breaches.holes, hasLength(1), reason: 'remembered, cut nothing');
    });

    test('is in the snapshot and comes back from it', () {
      final level = _rooms();
      final world = CollisionWorld();
      level.addTo(world);
      world.update();
      final breaches = Breaches(level, world)
        ..blast(Vector3(8.0, 1.0, 4.0), Vector3(-1.0, 0.0, 0.0));
      final saved = breaches.save();
      final cut = _volume(breaches.brushes);

      // A fresh level, restored into.
      final again = Level.fromJson(level.toJson());
      final world2 = CollisionWorld();
      again.addTo(world2);
      world2.update();
      final restored = Breaches(again, world2)..restore(saved);
      world2.update();

      expect(restored.holes, hasLength(1));
      expect(_volume(restored.brushes), closeTo(cut, 1e-4));
      final hit = RayHit();
      expect(
        world2.raycast(
          Vector3(4.0, 1.0, 4.0),
          Vector3(1.0, 0.0, 0.0),
          10.0,
          hit,
        ),
        isFalse,
        reason: 'the hole is there again',
      );
      expect(world2.staticCount, restored.brushes.length);
    });

    test('restoring an empty snapshot heals the level', () {
      final level = _rooms();
      final world = CollisionWorld();
      level.addTo(world);
      world.update();
      final breaches = Breaches(level, world)
        ..blast(Vector3(8.0, 1.0, 4.0), Vector3(-1.0, 0.0, 0.0));

      breaches.restore(<String, Object?>{'holes': <Object?>[]});
      world.update();

      expect(breaches.brushes, level.brushes);
      expect(world.staticCount, level.brushes.length);
    });
  });
}
