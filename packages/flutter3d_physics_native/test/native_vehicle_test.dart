/// A vehicle on a native world through `dart:ffi`: the C tests hold the
/// springs, the drive, the steering and the tyres against their physics;
/// this holds the binding — a car made, driven, read and taken away.
library;

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  late NativeWorld world;
  setUp(() {
    world = NativeWorld()..setAir(temperature: 293.15, density: 1e-30);
    final floor = world.addBody(
      position: Vector3(0.0, -0.5, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setShape(floor, NativeShape.box(Vector3(200.0, 0.5, 200.0)));
  });
  tearDown(() => world.dispose());

  test('a car stands on four springs, drives off, and reports its wheels', () {
    final chassis = world.addBody(
      position: Vector3(0.0, 1.0, 0.0),
      mass: 1200.0,
    );
    world.setShape(chassis, NativeShape.box(Vector3(0.9, 0.3, 2.0)));
    final car = world.createVehicle(chassis);
    for (final (x, z) in const <(double, double)>[
      (-0.8, 1.3),
      (0.8, 1.3),
      (-0.8, -1.3),
      (0.8, -1.3),
    ]) {
      world.addWheel(
        car,
        NativeWheelSettings(
          attach: Vector3(x, -0.2, z),
          rest: 0.4,
          radius: 0.35,
          stiffness: 30000.0,
          damping: 3000.0,
          grip: 1.0,
        ),
      );
    }
    expect(world.wheelCount(car), 4);
    for (var i = 0; i < 180; i++) {
      world.step(1.0 / 60.0);
    }
    // Mutation: the wheels' rays read as length, not distance — the car
    // sits a radius lower.
    final squeeze = 1200.0 * 9.81 / 4.0 / 30000.0;
    expect(world.positionOf(chassis).y, closeTo(0.95 - squeeze, 2e-3));
    final standing = world.wheelsOf(car);
    expect(standing.every((w) => w.touching), isTrue);
    // The chassis falls asleep within a millimetre of rest, its springs
    // read where it stopped: a millimetre of a 30 kN/m spring is 30 N, about
    // one per cent of statics.
    expect(standing.first.force, closeTo(1200.0 * 9.81 / 4.0, 30.0));
    expect(standing.first.center.y, closeTo(0.35, 2e-3));
    world
      ..setWheel(car, 2, drive: 1200.0)
      ..setWheel(car, 3, drive: 1200.0)
      ..setWheel(car, 0, steer: 0.1)
      ..setWheel(car, 1, steer: 0.1);
    for (var i = 0; i < 60; i++) {
      world.step(1.0 / 60.0);
    }
    // F / m is two metres a second each second; a little goes into the
    // chassis squatting onto its rear springs as it sets off.
    expect(world.velocityOf(chassis).length, inInclusiveRange(1.8, 2.0));
    expect(world.wheelsOf(car).first.steer, closeTo(0.1, 1e-7));
    expect(() => world.setWheel(car, 4), throwsArgumentError);
    expect(() => world.setWheel(car, 0, brake: -1.0), throwsArgumentError);
    expect(world.removeVehicle(car), isTrue);
    expect(world.containsVehicle(car), isFalse);
    expect(world.wheelsOf(car), isEmpty);
  });

  test('a fixed body is not a chassis', () {
    final post = world.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    expect(() => world.createVehicle(post), throwsArgumentError);
  });
}
