/// A throw aimed by the core's own flight: what a volcano's bombs and a
/// siege's stones are thrown with, so no game keeps a vacuum's formula and a
/// number to make up for the air.
///
///     dart test test/ballistics_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Where [solid] thrown from [from] at [velocity] in [world] comes down
/// through [height], flown in a game's own elements at [step].
Vector3 _landing(
  NativeWorld world,
  Solid solid,
  Vector3 from,
  Vector3 velocity,
  double height, {
  double step = 1 / 60,
}) {
  final elements = ElementsSimulation.adopt(world);
  final body = elements.addBody(solid, at: from, velocity: velocity);
  var before = from.clone();
  for (var t = 0.0; t < 60.0; t += step) {
    world.step(step);
    final now = world.localPositionOf(body);
    if (now.y <= height && world.velocityOf(body).y < 0.0) {
      final share = (before.y - height) / (before.y - now.y);
      return before + (now - before) * share;
    }
    before = now;
  }
  fail('never came down');
}

void main() {
  test('a throw comes down on its mark through the air, where a vacuum\'s '
      'formula falls short', () {
    // Hollow's bombs were thrown by v² = g·D²/(D + h), with no air. The
    // core drags a ball through its world's air, so that throw lands short.
    // Mutation: return the vacuum's speed — the flight lands metres short
    // and the first expectation fails.
    final world = NativeWorld()..applyProperties(WorldProperties.standard);
    addTearDown(world.dispose);
    final bomb = Solid.of(const NativeShape.sphere(0.35), Materials.basaltMelt);
    final from = Vector3(0.0, 17.0, 0.0);
    final to = Vector3(24.0, 2.0, 7.0);
    final throw_ = Ballistics.aim(
      world,
      bomb,
      from: from,
      to: to,
      elevation: math.pi / 4,
    );
    final landed = _landing(world, bomb, from, throw_, to.y);
    expect((landed - to).length, lessThan(0.05));

    // What the vacuum's formula throws at, and how short the air leaves
    // it: the number a game had to keep.
    final reach = math.sqrt(24.0 * 24.0 + 7.0 * 7.0);
    final vacuum = reach * math.sqrt(world.gravityMagnitude / (reach + 15.0));
    expect(throw_.length, greaterThan(vacuum * 1.001));
    final short = _landing(
      world,
      bomb,
      from,
      throw_.normalized() * vacuum,
      to.y,
    );
    expect((short - to).length, greaterThan(0.1));
  });

  test('the lighter and larger a thing, the harder it is thrown', () {
    // Mutation: fly every throw as a point mass — both need the same.
    final world = NativeWorld()..applyProperties(WorldProperties.standard);
    addTearDown(world.dispose);
    Vector3 aim(Solid solid) => Ballistics.aim(
      world,
      solid,
      from: Vector3.zero(),
      to: Vector3(30.0, 0.0, 0.0),
      elevation: math.pi / 4,
    );
    final stone = Solid.of(const NativeShape.sphere(0.1), Materials.granite);
    final cork = Solid.of(const NativeShape.sphere(0.1), Materials.cork);
    expect(aim(cork).length, greaterThan(aim(stone).length * 1.05));
  });

  test('a mark the elevation cannot reach is refused', () {
    final world = NativeWorld();
    addTearDown(world.dispose);
    expect(
      () => Ballistics.aim(
        world,
        Solid.of(const NativeShape.sphere(0.1), Materials.granite),
        from: Vector3.zero(),
        to: Vector3(5.0, 10.0, 0.0),
        elevation: 0.3,
      ),
      throwsArgumentError,
    );
  });
}
