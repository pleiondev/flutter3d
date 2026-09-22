/// A level's field of heights, as something a body can stand on.
///
///     dart test test/ground_collision_test.dart
///
/// `Level.addTo` added the brushes and nothing else, so a level whose ground
/// was a field drew a hill and collided with none of it. The shape that stands
/// for a field in the collision world is described from its middle, and the
/// field in the document from a corner, so what these tests hold is the one
/// thing that can go wrong when the two are joined: the ground being somewhere
/// other than where [Heightfield.heightAt] says it is.
library;

import 'dart:typed_data';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A field that is level nowhere and symmetric about nothing, so an answer
/// taken from the wrong cell, the wrong axis or the wrong corner is a different
/// number rather than a lucky one.
Heightfield _ground({Vector3? origin}) {
  const columns = 6;
  const rows = 5;
  return Heightfield(
    columns: columns,
    rows: rows,
    cellSize: 2.0,
    origin: origin,
    heights: Float32List.fromList(<double>[
      for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++)
          3.0 + column * 0.75 - row * 0.4 + (column * row).isOdd.toDouble(),
    ]),
  );
}

Level _level(Heightfield? ground, {List<Brush> brushes = const <Brush>[]}) =>
    Level(
      name: 'ground',
      materials: <String, LevelMaterial>{'stone': LevelMaterial()},
      brushes: brushes,
      entities: const <EntityDef>[],
      heightfield: ground,
    );

extension on bool {
  double toDouble() => this ? 1.0 : 0.0;
}

/// Where a ray fired straight down over `(x, z)` lands, or null if on nothing.
double? _landing(CollisionWorld world, double x, double z) {
  final hit = RayHit();
  final met = world.raycast(
    Vector3(x, 100.0, z),
    Vector3(0.0, -1.0, 0.0),
    200.0,
    hit,
  );
  return met ? hit.point.y : null;
}

void main() {
  test('a level with a field of heights has ground in its world', () {
    final ground = _ground();
    final world = CollisionWorld();
    _level(ground).addTo(world);

    final hit = RayHit();
    expect(
      world.raycast(
        Vector3(3.0, 50.0, 3.0),
        Vector3(0.0, -1.0, 0.0),
        100.0,
        hit,
      ),
      isTrue,
      reason: 'the hill was drawn and there was nothing under it',
    );
    expect(hit.collider?.userData, same(ground));
  });

  test('the ground is where the field says it is, all the way across', () {
    final ground = _ground(origin: Vector3(-7.0, 0.0, 11.0));
    final world = CollisionWorld();
    _level(ground).addTo(world);

    // Inside the rim by a hair: on it, a vertical ray runs along the field's
    // own side face and what it meets first is not the question being asked.
    const inset = 0.05;
    for (var i = 0; i <= 8; i++) {
      for (var j = 0; j <= 8; j++) {
        final x = ground.origin.x + inset + (ground.width - 2 * inset) * i / 8;
        final z = ground.origin.z + inset + (ground.depth - 2 * inset) * j / 8;
        expect(
          _landing(world, x, z),
          closeTo(ground.heightAt(x, z), 1e-4),
          reason: 'at ($x, $z)',
        );
      }
    }
  });

  test('a height in the origin lifts nothing, as it lifts nothing drawn', () {
    // Neither `heightAt` nor the mesh builder adds `origin.y` to a sample. The
    // collider follows them rather than the field's doc comment, because a
    // ground that agrees with the comment and with no picture is a body
    // standing in the air.
    final flat = _ground();
    final lifted = _ground(origin: Vector3(0.0, 40.0, 0.0));
    final world = CollisionWorld();
    _level(lifted).addTo(world);

    expect(lifted.heightAt(5.0, 3.0), flat.heightAt(5.0, 3.0));
    expect(_landing(world, 5.0, 3.0), closeTo(lifted.heightAt(5.0, 3.0), 1e-4));
  });

  test('a level without one adds what it always added', () {
    final world = CollisionWorld();
    _level(
      null,
      brushes: <Brush>[
        Brush(
          centre: Vector3(0.0, -0.5, 0.0),
          size: Vector3(10.0, 1.0, 10.0),
          material: 'stone',
        ),
      ],
    ).addTo(world);

    expect(_landing(world, 1.0, 1.0), closeTo(0.0, 1e-6));
    expect(_landing(world, 40.0, 40.0), isNull);
  });

  test(
    'editing the field afterwards does not move the ground under a body',
    () {
      final samples = Float32List.fromList(List<double>.filled(9, 1.0));
      final ground = Heightfield(
        columns: 3,
        rows: 3,
        cellSize: 1.0,
        heights: samples,
      );
      final world = CollisionWorld();
      _level(ground).addTo(world);

      samples[4] = 25.0;

      expect(ground.heightAt(1.0, 1.0), 25.0);
      expect(
        _landing(world, 1.0, 1.0),
        closeTo(1.0, 1e-4),
        reason:
            'the shape measured its bounds once; a shared list would leave it '
            'indexed by numbers it never saw',
      );
    },
  );
}
