/// Heat, fire and wind on a native world through `dart:ffi` — P9.
///
///     dart test test/native_heat_test.dart
///
/// The C tests hold the arithmetic; these hold what a game reads through
/// the binding: a block of wood that catches, burns, smokes and is put out,
/// and the wind that carries and cools.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  late NativeWorld world;
  setUp(() => world = NativeWorld());
  tearDown(() => world.dispose());

  NativeBody woodBlock() {
    final b = world.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
      mass: 0.6,
    );
    world
      ..setShape(b, NativeShape.box(Vector3.all(0.05)))
      ..setMaterial(b, NativeMaterial.wood());
    return b;
  }

  test(
    'the presets are the core\'s, and a material out of range is refused',
    () {
      final wood = NativeMaterial.wood();
      expect(wood.ignitionTemperature, closeTo(573.15, 1e-3));
      expect(wood.fuelFraction, closeTo(0.8, 1e-6));
      expect(NativeMaterial.steel().ignitionTemperature, 0.0);
      expect(NativeMaterial.paper().ignitionTemperature, closeTo(506.15, 1e-3));
      final b = world.addBody(position: Vector3.zero(), mass: 2.0);
      expect(
        () => world.setMaterial(
          b,
          const NativeMaterial(specificHeat: 1000.0, fuelFraction: 1.0),
        ),
        throwsArgumentError,
      );
      world.setMaterial(b, wood);
      expect(world.fuelOf(b), closeTo(1.6, 1e-6));
      expect(world.temperatureOf(b), closeTo(293.15, 1e-4));
    },
  );

  test('a block of wood catches, burns, smokes and burns out', () {
    // Mutation: drop the flame's share in `f3d_step_heat` — the block cools
    // from 600 K straight back below its ignition point and goes out.
    final block = woodBlock();
    world.setTemperature(block, 600.0);
    world.step(0.1);
    expect(world.isBurning(block), isTrue);
    expect(world.readEvents(), <NativeEvent>[
      (body: block, other: null, kind: NativeEventKind.ignited),
    ]);
    for (var i = 0; i < 600; i++) {
      world.step(0.1);
    }
    expect(world.isBurning(block), isTrue);
    // It heats itself well past its ignition point.
    expect(world.temperatureOf(block), greaterThan(700.0));
    // Eleven grams a second per square metre of its 0.06 m², fifteen
    // megajoules a kilogram, seven tenths of it leaving as gas.
    const rate = 0.011 * 0.06;
    expect(world.heatReleaseOf(block), closeTo(0.7 * rate * 1.5e7, 0.01));
    final fires = world.readFires();
    expect(fires.bodies, <NativeBody>[block]);
    expect(fires.fires[3], world.heatReleaseOf(block));
    expect(world.massOf(block), closeTo(0.6 - rate * 60.0, 1e-4));
    var steps = 0;
    while (world.isBurning(block) && steps < 10000) {
      world.step(0.1);
      steps++;
    }
    expect(world.fuelOf(block), 0.0);
    expect(world.massOf(block), closeTo(0.12, 1e-4));
    expect(world.readEvents().single.kind, NativeEventKind.burntOut);
    expect(world.readFires().bodies, isEmpty);
  });

  test('water keeps wood from catching, and puts a fire out', () {
    final wet = woodBlock();
    world.addWater(wet, 0.05);
    expect(world.waterOf(wet), closeTo(0.05, 1e-7));
    var boiling = false;
    while (world.waterOf(wet) > 0.0) {
      world
        ..addHeat(wet, 2000.0)
        ..step(0.1);
      expect(world.isBurning(wet), isFalse);
      if (world.waterOf(wet) > 0.0) {
        expect(world.temperatureOf(wet), lessThanOrEqualTo(373.15 + 1e-3));
        boiling |= world.temperatureOf(wet) > 373.14;
      }
    }
    expect(boiling, isTrue);
    while (!world.isBurning(wet)) {
      world
        ..addHeat(wet, 2000.0)
        ..step(0.1);
    }
    world.readEvents();
    for (var i = 0; i < 100; i++) {
      world.step(0.1);
    }
    world
      ..addWater(wet, 0.5)
      ..step(0.1);
    expect(world.isBurning(wet), isFalse);
    expect(world.readEvents(), <NativeEvent>[
      (body: wet, other: null, kind: NativeEventKind.extinguished),
    ]);
  });

  test('a ball falls to its terminal speed in still air', () {
    final ball = world.addBody(position: Vector3.zero(), mass: 0.05);
    world
      ..setSleep(speed: 0.0, time: 0.0)
      ..setShape(ball, const NativeShape.sphere(0.1));
    for (var i = 0; i < 3000; i++) {
      world.step(1.0 / 60.0);
    }
    final terminal = math.sqrt(
      2.0 * 0.05 * 9.81 / (1.204 * 0.47 * math.pi * 0.01),
    );
    expect(-world.velocityOf(ball).y, closeTo(terminal, terminal * 1e-4));
  });

  test('the wind carries what it blows on, and cools it', () {
    world.gravity = Vector3.zero();
    world.setWindGrid(
      origin: Vector3.zero(),
      cell: 10.0,
      nx: 2,
      ny: 1,
      nz: 1,
      velocities: Float32List.fromList(<double>[0, 0, 0, 10, 0, 0]),
    );
    expect(world.windAt(Vector3(5.0, 0.0, 0.0)).x, 5.0);
    world.wind = Vector3(0.0, 0.0, 1.0);
    expect(world.windAt(Vector3(10.0, 3.0, 0.0)), Vector3(10.0, 0.0, 1.0));
    final still = world.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
      mass: 1.0,
    );
    final windy = world.addBody(
      position: Vector3(10.0, 0.0, 0.0),
      type: NativeBodyType.fixed,
      mass: 1.0,
    );
    final leaf = world.addBody(position: Vector3(10.0, 0.0, 0.0), mass: 1e-3);
    for (final b in <NativeBody>[still, windy, leaf]) {
      world
        ..setShape(b, const NativeShape.sphere(0.05))
        ..setTemperature(b, 400.0);
    }
    for (var i = 0; i < 60; i++) {
      world.step(1.0 / 60.0);
    }
    expect(world.temperatureOf(windy), lessThan(world.temperatureOf(still)));
    expect(world.velocityOf(leaf).x, greaterThan(5.0));
    expect(world.velocityOf(leaf).x, lessThan(10.0));
    expect(
      () => world.setWindGrid(
        origin: Vector3.zero(),
        cell: 1.0,
        nx: 2,
        ny: 1,
        nz: 1,
        velocities: Float32List(3),
      ),
      throwsArgumentError,
    );
    world.clearWindGrid();
    expect(world.windAt(Vector3(10.0, 0.0, 0.0)), Vector3(0.0, 0.0, 1.0));
    expect(
      () => world.setAir(temperature: -1.0, density: 1.0),
      throwsArgumentError,
    );
    world.setAir(temperature: 250.0, density: 1.3);
    expect(world.airTemperature, 250.0);
    expect(world.airDensity, closeTo(1.3, 1e-6));
  });
}
