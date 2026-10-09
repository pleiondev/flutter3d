/// A multibody on a native world through `dart:ffi`: the C tests hold the
/// period, the chain, the limits, the motors and the snapshot against their
/// physics; this holds the binding — a chain made, swung, read and taken
/// away.
library;

import 'dart:math' as math;

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  late NativeWorld world;
  setUp(() {
    world = NativeWorld()
      ..setAir(temperature: 293.15, density: 1e-30)
      ..setSleep(speed: 0.0, time: 0.0);
  });
  tearDown(() => world.dispose());

  test('a chain of five hinges swings down and keeps every joint together', () {
    final top = world.addBody(
      position: Vector3(0.0, 5.0, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setShape(top, NativeShape.box(Vector3.all(0.05)));
    final chain = world.createMultibody(top);
    final links = <NativeBody>[];
    for (var k = 1; k <= 5; k++) {
      final link = world.addBody(position: Vector3(k * 0.4 - 0.2, 5.0, 0.0));
      world.setShape(link, NativeShape.box(Vector3(0.2, 0.03, 0.03)));
      expect(
        world.addLink(
          chain,
          link,
          parent: k - 1,
          type: NativeJointType.revolute,
          anchor: Vector3((k - 1) * 0.4, 5.0, 0.0),
          axis: Vector3(0.0, 0.0, 1.0),
        ),
        k,
      );
      links.add(link);
    }
    expect(world.linkCount(chain), 6);
    expect(world.dofCount(chain), 5);
    world.setLinkLimits(chain, 1, lower: -1.2, upper: 1.2);
    for (var i = 0; i < 120; i++) {
      world.step(1.0 / 60.0);
    }
    // Mutation: the joints not read back — the shoulder reads nought.
    final shoulder = world.linkJoint(chain, 1);
    expect(shoulder.position, inInclusiveRange(-1.2001, -0.5));
    // Each link's far end is its neighbour's near end.
    for (var k = 1; k < links.length; k++) {
      final a =
          world.localPositionOf(links[k - 1]) +
          world
              .orientationOf(links[k - 1])
              .asRotationMatrix()
              .transformed(Vector3(0.2, 0.0, 0.0));
      final b =
          world.localPositionOf(links[k]) +
          world
              .orientationOf(links[k])
              .asRotationMatrix()
              .transformed(Vector3(-0.2, 0.0, 0.0));
      expect((a - b).length, lessThan(1e-4));
    }
    expect(
      () => world.addLink(
        chain,
        links.first,
        type: NativeJointType.revolute,
        anchor: Vector3.zero(),
      ),
      throwsArgumentError,
    );
    expect(
      () => world.setLinkLimits(chain, 0, lower: -1.0, upper: 1.0),
      throwsArgumentError,
    );
    expect(world.removeMultibody(chain), isTrue);
    expect(world.containsMultibody(chain), isFalse);
  });

  test('a motor on an upright axle brings a wheel to its speed', () {
    final axle = world.addBody(
      position: Vector3(0.0, 1.0, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    final wheel = world.addBody(position: Vector3(0.0, 1.0, 0.0), mass: 2.0);
    world.setShape(wheel, const NativeShape.cylinder(0.5, 0.05));
    final spun = world.createMultibody(axle);
    world
      ..addLink(
        spun,
        wheel,
        type: NativeJointType.revolute,
        anchor: Vector3(0.0, 1.0, 0.0),
      )
      ..setLinkMotor(spun, 1, speed: 2.0, force: 50.0);
    for (var i = 0; i < 60; i++) {
      world.step(1.0 / 60.0);
    }
    expect(world.linkJoint(spun, 1).speed, closeTo(2.0, 1e-3));
    // Taken off, nothing holds the speed but the wheel's own spin.
    world.setLinkMotor(spun, 1);
    expect(() => world.setLinkMotor(spun, 0, speed: 1.0), throwsArgumentError);
  });

  test('a spherical link reads its turn and spin', () {
    final top = world.addBody(
      position: Vector3(0.0, 3.0, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    final bob = world.addBody(position: Vector3(1.0, 3.0, 0.0));
    world.setShape(bob, const NativeShape.sphere(0.1));
    final swing = world.createMultibody(top);
    world.addLink(
      swing,
      bob,
      type: NativeJointType.spherical,
      anchor: Vector3(0.0, 3.0, 0.0),
    );
    expect(world.dofCount(swing), 3);
    for (var i = 0; i < 20; i++) {
      world.step(1.0 / 60.0);
    }
    final turn = world.linkTurn(swing, 1);
    // Falling from level, it has turned about z, the negative way.
    expect(turn.turn.z, lessThan(-0.05));
    expect(turn.spin.z, lessThan(-0.5));
  });

  test('a cone keeps a ball joint from swinging out past it', () {
    final top = world.addBody(
      position: Vector3(0.0, 3.0, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    final bob = world.addBody(position: Vector3(0.0, 2.0, 0.0));
    world.setShape(bob, const NativeShape.sphere(0.1));
    final lamp = world.createMultibody(top);
    world
      ..addLink(
        lamp,
        bob,
        type: NativeJointType.spherical,
        anchor: Vector3(0.0, 3.0, 0.0),
        axis: Vector3(0.0, -1.0, 0.0),
      )
      ..setLinkCone(lamp, 1, swing: 0.5, twist: 0.3)
      ..setVelocity(bob, Vector3(4.0, 0.0, 0.0));
    var most = 0.0;
    for (var i = 0; i < 60; i++) {
      world.step(1.0 / 60.0);
      // How far the rod is from straight down.
      final rod = world.localPositionOf(bob) - Vector3(0.0, 3.0, 0.0);
      most = math.max(most, math.acos(-rod.y / rod.length));
    }
    // Mutation: the cone not passed to the core — it swings past a radian.
    expect(most, inInclusiveRange(0.45, 0.51));
    expect(() => world.setLinkCone(lamp, 1, swing: 0.0), throwsArgumentError);
    world.setLinkCone(lamp, 1);
  });
}
