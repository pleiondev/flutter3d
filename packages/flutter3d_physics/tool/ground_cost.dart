/// What sweeping against sampled ground costs, beside sweeping against a box.
///
///     dart run tool/ground_cost.dart
///
/// **The number that decides whether ground can be a collision shape at all.**
/// A field of triangles is not one convex solid, so every sweep against it
/// walks several prisms instead of one set of planes, and "several" is decided
/// by how much ground the swept box covers. A body a third of a metre across
/// moving a tenth of a metre a step touches one or two cells, which is two or
/// four triangles — but that is an argument, and this is the measurement.
///
/// ## What was measured, on macOS-arm64, Dart 3.12, 2026-09-08
///
/// One sweep of a player-sized box onto the surface, averaged over two hundred
/// thousand of them, microseconds each — two runs, and they agreed to within
/// three per cent:
///
///     against one box                       0.13
///     against ground, 1 m cells             0.53   (4.1x)
///     against ground, 4 m cells             0.31   (2.4x)
///     against ground, 1 m cells, a capsule  0.48
///
/// And the step those add up to, sixty thousand of them:
///
///     a walking body over one box           0.52
///     a walking body over ground            3.5    (6.7x)
///
/// **Four times a brush for one sweep, and nearly seven times for a step.** The
/// step is the worse ratio because a controller makes four or five sweeps and a
/// depenetration in one, and each of them now walks four to eight prisms where
/// it used to walk one box. Three and a half microseconds is still a
/// three-hundredth of a sixtieth of a second, so a hundred bodies walking on
/// ground is a fifth of a frame — comfortable for a strategy and worth knowing
/// before somebody puts a thousand there.
///
/// **The cell size is the dial, and it is the level's.** Wider cells mean fewer
/// triangles under a body and a coarser surface; the difference between one
/// metre and four is nearly a factor of two, and it is what a level author is
/// choosing between without being told.
///
/// The capsule being *cheaper* than the box it fits in reads backwards. It
/// walks exactly the same prisms — the broadphase asks the bounding box, and
/// the two have the same one — so the tenth is in the growth: a capsule's reach
/// along a normal is one multiply and an add, and a box's is three of each.
///
/// ## What is not measured here
///
/// A triangle mesh. There is not one: `CollisionHeightfield` is the whole of
/// what this package can be handed as ground, and a general mesh — which needs
/// a spatial index inside the shape rather than a grid it already is — has not
/// been written. The row it would occupy in the table above is missing rather
/// than estimated.
library;

import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

const int _sweeps = 200000;

CollisionWorld _ground(double cellSize) {
  const n = 65;
  final heights = Float32List(n * n);
  for (var row = 0; row < n; row++) {
    for (var column = 0; column < n; column++) {
      heights[row * n + column] =
          0.06 * ((column * 5 + row * 3) % 7) +
          0.04 * ((column * 3 + row * 11) % 5);
    }
  }
  final world = CollisionWorld()
    ..add(
      Collider(
        shape: CollisionHeightfield(
          columns: n,
          rows: n,
          cellSize: cellSize,
          heights: heights,
        ),
        position: Vector3.zero(),
      ),
    );
  world.update();
  return world;
}

/// One brush the same size as the whole field, so the broadphase has the same
/// amount of work to do and the difference is the narrow phase alone.
CollisionWorld _brush(double cellSize) {
  final span = 64.0 * cellSize;
  final world = CollisionWorld()
    ..addBox(Vector3(0.0, -1.0, 0.0), Vector3(span, 2.0, span));
  world.update();
  return world;
}

/// Sweeps [shape] downward from a walk across the field, and returns the
/// microseconds one sweep took.
double _cost(CollisionWorld world, CollisionShape shape, double span) {
  final hit = SweepHit();
  final from = Vector3.zero();
  // Down onto the surface and a little along it: the shape of the probe the
  // ground check makes, and long enough to actually land. A sweep that misses
  // is a sweep that stops at the first rejection, which would measure the
  // broadphase rather than the geometry.
  final delta = Vector3(0.05, -1.6, 0.03);
  var landed = 0;
  final clock = Stopwatch()..start();
  for (var i = 0; i < _sweeps; i++) {
    // A walk that covers the field rather than one spot, so the measurement is
    // not of one cell staying in the cache.
    final t = i / _sweeps;
    from.setValues(
      (t * span * 7.0) % span - span * 0.5,
      2.0,
      (t * span * 3.0) % span - span * 0.5,
    );
    if (world.sweep(shape, from, delta, hit)) landed++;
  }
  clock.stop();
  if (landed < _sweeps) {
    // ignore: avoid_print
    print('  (only $landed of $_sweeps sweeps landed on anything)');
  }
  return clock.elapsedMicroseconds / _sweeps;
}

/// A whole step of a walking body, which is what the sweep cost adds up to.
double _stepCost(CollisionWorld world) {
  final walker = CharacterController(
    world: world,
    position: Vector3(0.0, 2.0, 0.0),
  );
  final wish = Vector3(1.0, 0.0, 0.35);
  const steps = 60000;
  final clock = Stopwatch()..start();
  for (var i = 0; i < steps; i++) {
    walker.step(1.0 / 60.0, wishDirection: wish);
    if (walker.position.x > 24.0 || walker.position.z > 24.0) {
      walker.teleport(Vector3(-24.0, 2.0, -24.0));
    }
  }
  clock.stop();
  return clock.elapsedMicroseconds / steps;
}

void main() {
  final body = CollisionBox(Vector3(0.35, 0.9, 0.35));
  final capsule = CollisionCapsule(radius: 0.35, halfHeight: 0.55);

  final fine = _ground(1.0);
  final coarse = _ground(4.0);
  final flat = _brush(1.0);

  // Warm, then measure: the first pass is the JIT's.
  _cost(flat, body, 64.0);
  _cost(fine, body, 64.0);
  _cost(coarse, body, 256.0);

  final box = _cost(flat, body, 64.0);
  final ground = _cost(fine, body, 64.0);
  final wide = _cost(coarse, body, 256.0);
  final rounded = _cost(fine, capsule, 64.0);

  _stepCost(_brush(1.0));
  _stepCost(_ground(1.0));
  final walkFlat = _stepCost(_brush(1.0));
  final walkGround = _stepCost(_ground(1.0));

  // ignore: avoid_print
  print(
    'microseconds a sweep, over $_sweeps of them\n'
    '  against one box                       ${box.toStringAsFixed(3)}\n'
    '  against ground, 1 m cells             ${ground.toStringAsFixed(3)}'
    '   (${(ground / box).toStringAsFixed(1)}x)\n'
    '  against ground, 4 m cells             ${wide.toStringAsFixed(3)}'
    '   (${(wide / box).toStringAsFixed(1)}x)\n'
    '  against ground, 1 m cells, a capsule  ${rounded.toStringAsFixed(3)}\n'
    '\nmicroseconds a step of a walking body\n'
    '  over one box                          ${walkFlat.toStringAsFixed(3)}\n'
    '  over ground, 1 m cells                ${walkGround.toStringAsFixed(3)}'
    '   (${(walkGround / walkFlat).toStringAsFixed(1)}x)',
  );
}
