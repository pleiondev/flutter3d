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
      expect(wood.ignitionTemperature, closeTo(663.15, 1e-3));
      expect(wood.charYield, closeTo(0.18, 1e-6));
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
      // A rubber fire is sootier than a wood fire: more of its heat leaves
      // as radiation, through a flame that absorbs more.
      final rubber = NativeMaterial.rubber();
      // McCaffrey's mean continuous-flame gas, as f3d_heat.c cites it.
      expect(wood.flameTemperature, closeTo(1090.15, 1e-3));
      expect(rubber.flameRadiant, greaterThan(wood.flameRadiant));
      expect(rubber.flameAbsorption, greaterThan(wood.flameAbsorption));
      // A flame no hotter than the material catches at is refused.
      expect(
        () => world.setMaterial(
          b,
          NativeMaterial(
            specificHeat: wood.specificHeat,
            ignitionTemperature: wood.ignitionTemperature,
            heatOfCombustion: wood.heatOfCombustion,
            burnRate: wood.burnRate,
            fuelFraction: wood.fuelFraction,
            flameTemperature: 500.0,
          ),
        ),
        throwsArgumentError,
      );
      world.setMaterial(b, wood);
      expect(world.fuelOf(b), closeTo(1.6, 1e-6));
      expect(world.temperatureOf(b), closeTo(293.15, 1e-4));
    },
  );

  test('a block of wood catches, burns on its char, and goes out', () {
    // Mutation: drop the flame's share in `f3d_step_heat` — the block cools
    // from 690 K straight back below its ignition point and goes out.
    final block = woodBlock();
    world.setTemperature(block, 690.0);
    world.step(0.1);
    expect(world.isBurning(block), isTrue);
    expect(world.readEvents(), <NativeEvent>[
      (body: block, other: null, kind: NativeEventKind.ignited),
    ]);
    for (var i = 0; i < 600; i++) {
      world.step(0.1);
    }
    expect(world.isBurning(block), isTrue);
    // It burns on a char layer that glows well past its ignition point,
    // ahead of its middle — Mikkola measured 680 °C on burning wood's char.
    expect(world.surfaceTemperatureOf(block), greaterThan(700.0));
    expect(
      world.surfaceTemperatureOf(block),
      greaterThan(world.temperatureOf(block)),
    );
    expect(world.heatReleaseOf(block), greaterThan(0.0));
    // Mutation: return `involved` in place of `charred` in
    // `f3d_body_get_char` — the char is gone the moment the fire is.
    final char = world.charOf(block);
    expect(char.share, greaterThan(0.5));
    expect(char.depth, greaterThan(0.0));
    expect(char.temperature, greaterThan(663.15));
    final fires = world.readFires();
    expect(fires.bodies, <NativeBody>[block]);
    expect(fires.fires.length, nativeFireFloats);
    expect(fires.fires[3], world.heatReleaseOf(block));
    // Its flame stands over it, straight up in still air.
    expect(fires.fires[4], greaterThan(0.0));
    expect(fires.fires[5], closeTo(0.0, 1e-6));
    expect(fires.fires[6], closeTo(1.0, 1e-6));
    expect(fires.fires[7], closeTo(0.0, 1e-6));
    expect(world.massOf(block), lessThan(0.6));
    // Alone, with nothing else's heat on it, it goes out with wood left
    // under its char: a lone block does not burn itself away.
    var steps = 0;
    while (world.isBurning(block) && steps < 20000) {
      world.step(0.1);
      steps++;
    }
    expect(world.isBurning(block), isFalse);
    expect(world.fuelOf(block), greaterThan(0.0));
    expect(world.readEvents().single.kind, NativeEventKind.extinguished);
    expect(world.readFires().bodies, isEmpty);
    expect(world.charOf(block).share, greaterThanOrEqualTo(char.share));
  });

  test('a red-hot stone on thatch sets it burning on', () {
    // Straw as a bed of fine elements, Anderson's tall grass: σ = 4921 1/m,
    // ρ_p = 513 kg/m³. Mutation: drop `elementSurface` from `write` — the
    // roof is a solid slab of paper again, and its fire goes out under its
    // own char within half a minute.
    final roof = world.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
      mass: 800.0,
    );
    world
      ..setShape(roof, NativeShape.box(Vector3(2.3, 0.2, 2.3)))
      ..setMaterial(
        roof,
        NativeMaterial.paper().copyWith(
          elementSurface: 4921.0,
          elementDensity: 513.0,
        ),
      );
    final stone = world.addBody(position: Vector3(0.0, 0.55, 0.0), mass: 400.0);
    world
      ..setShape(stone, const NativeShape.sphere(0.35))
      ..setMaterial(stone, NativeMaterial.stone())
      ..setTemperature(stone, 1300.0);
    for (var i = 0; i < 30 * 60; i++) {
      world.step(1.0 / 60.0);
    }
    expect(world.isBurning(roof), isTrue);
    expect(world.heatReleaseOf(roof), greaterThan(1e5));
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
      // Its surface is held at boiling while the water boils off.
      if (world.waterOf(wet) > 0.0) {
        final surface = world.surfaceTemperatureOf(wet);
        expect(surface, lessThanOrEqualTo(373.15 + 1e-3));
        boiling |= surface > 373.14;
      }
    }
    expect(boiling, isTrue);
    // Dry now, and heated through past its ignition point, it catches and
    // burns on.
    world
      ..setTemperature(wet, 690.0)
      ..step(0.1);
    expect(world.isBurning(wet), isTrue);
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

  test('a post burns upwards a part at a time', () {
    // Five boxes stood on end, one body: lit at the bottom, each part catches
    // in the flame of the one below, and the top is still cold when the
    // second part catches.
    final post = world.addBody(
      position: Vector3(0.0, 1.0, 0.0),
      type: NativeBodyType.fixed,
      mass: 16.0,
    );
    world
      ..setCompound(
        post,
        world.createCompound(<NativeCompoundPart>[
          for (var k = 0; k < 5; k++)
            NativeCompoundPart(
              NativeShape.box(Vector3(0.05, 0.2, 0.05)),
              at: Vector3(0.0, -0.8 + 0.4 * k, 0.0),
            ),
        ]),
      )
      ..setMaterial(post, NativeMaterial.wood())
      ..setPartTemperature(post, 0, 690.0);
    expect(world.isPartBurning(post, 0), isFalse);
    var second = -1;
    var topThen = 0.0;
    for (var i = 0; i < 1200 && second < 0; i++) {
      world.step(1.0);
      if (world.isPartBurning(post, 1)) {
        second = i;
        topThen = world.partTemperatureOf(post, 4);
      }
    }
    // Mutation: one temperature for the whole post — it never catches, the
    // bottom's heat spread over all five.
    expect(second, greaterThan(0));
    expect(topThen, lessThan(400.0));
    expect(world.isBurning(post), isTrue);
    expect(() => world.partTemperatureOf(post, 5), throwsArgumentError);
    // A torch held to the top heats the top.
    final before = world.partTemperatureOf(post, 4);
    world
      ..addHeatAt(post, Vector3(0.0, 1.85, 0.0), 500000.0)
      ..step(0.01);
    expect(world.partTemperatureOf(post, 4), greaterThan(before + 50.0));
  });

  test('a material changed in one value keeps the rest', () {
    final wood = NativeMaterial.wood();
    final boards = wood.copyWith(flameSpread: 20000.0);
    expect(boards.flameSpread, 20000.0);
    expect(boards.ignitionTemperature, wood.ignitionTemperature);
    expect(boards.heatOfGasification, wood.heatOfGasification);
    expect(wood.heatOfGasification, greaterThan(0));
    expect(NativeMaterial.steel().modulus, closeTo(2e11, 1e6));
  });

  test('a burner burns on stone until it is put out', () {
    final stone = world.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
      mass: 10.0,
    );
    world
      ..setShape(stone, const NativeShape.sphere(0.1))
      ..setMaterial(stone, NativeMaterial.stone());
    final pine = NativeBurner(fuel: NativeMaterial.wood(), rate: 0.001);
    expect(pine.power, closeTo(15000.0, 1.0));
    expect(
      () => world.setBurner(
        stone,
        NativeBurner(fuel: NativeMaterial.stone(), rate: 0.001),
      ),
      throwsArgumentError,
    );
    world
      ..setBurner(stone, pine)
      ..step(0.1);
    expect(world.isBurning(stone), isTrue);
    for (var i = 0; i < 100; i++) {
      world.step(0.1);
    }
    // What burns, less what its flame hands the stone.
    final release = world.heatReleaseOf(stone);
    expect(release, inInclusiveRange(0.5 * pine.power, pine.power));
    world
      ..setBurner(stone, null)
      ..step(0.1);
    expect(world.isBurning(stone), isFalse);
  });

  test('a fire says the soot it makes a joule, its fuel\'s', () {
    // Mutation: read `sootYield` from float 11 in `fires` — it reads the
    // radiant share, a hundred million times too much.
    final block = woodBlock();
    world.setTemperature(block, 690.0);
    final stone = world.addBody(
      position: Vector3(3.0, 0.0, 0.0),
      type: NativeBodyType.fixed,
      mass: 10.0,
    );
    world
      ..setShape(stone, const NativeShape.sphere(0.1))
      ..setMaterial(stone, NativeMaterial.stone())
      ..setBurner(stone, NativeBurner.candle())
      ..step(0.1);
    final wood = NativeMaterial.wood(), wax = NativeMaterial.paraffin();
    final byBody = {for (final f in world.fires()) f.body: f};
    expect(
      byBody[block]!.sootYield,
      closeTo(wood.sootYield / wood.heatOfCombustion, 1e-15),
    );
    expect(
      byBody[stone]!.sootYield,
      closeTo(wax.sootYield / wax.heatOfCombustion, 1e-15),
    );
    expect(wood.sootYield, closeTo(0.015, 1e-7));
  });

  test('the new presets are the core\'s, and burn as their sources say', () {
    // Mutation: `oak()` reading the pine preset — oak catches at 588 K and
    // leaves 0.26 of itself as char, Tran and White's.
    final oak = NativeMaterial.oak();
    expect(oak.ignitionTemperature, closeTo(588.15, 1e-3));
    expect(oak.charYield, closeTo(0.26, 1e-6));
    expect(NativeMaterial.pine().ignitionTemperature, closeTo(593.15, 1e-3));
    expect(NativeMaterial.cardboard().heatOfCombustion, closeTo(14.03e6, 1.0));
    final thatch = NativeMaterial.thatch();
    expect(thatch.elementSurface, 5265.0);
    expect(thatch.elementDensity, 285.0);
    expect(NativeMaterial.charcoal().sootYield, 0.0);
    // A candle gives off 77 ± 9 W (Hamins, Bundy and Dillon). Mutation:
    // its rate ten times over.
    expect(NativeBurner.candle().power, closeTo(77.0, 9.0));
    // Gross's brazier crib, 1.24 g/s of pine at 13.9 MJ/kg; his kindling,
    // 0.128 g/s.
    expect(NativeBurner.brazier().power, closeTo(1.24e-3 * 13.9e6, 1.0));
    expect(NativeBurner.kindling().power, closeTo(1.28e-4 * 13.9e6, 0.1));
    expect(
      NativeBurner.bonfire().power,
      greaterThan(NativeBurner.campfire().power),
    );
    // A brazier of charcoal burns as fast as oxygen reaches its coals.
    final coals = NativeBurner.charcoal(0.2);
    expect(coals.rate, closeTo(0.2 * 1.02e-3, 1e-9));
    for (final m in <NativeMaterial>[
      oak,
      NativeMaterial.pine(),
      NativeMaterial.cardboard(),
      thatch,
      NativeMaterial.charcoal(),
      NativeMaterial.paraffin(),
    ]) {
      final b = world.addBody(position: Vector3.zero(), mass: 1.0);
      world.setMaterial(b, m);
    }
  });

  test('an explosion pushes by solid angle, away from it', () {
    world.gravity = Vector3.zero();
    NativeBody ball(double x) {
      final b = world.addBody(position: Vector3(x, 0.0, 0.0), mass: 1.0);
      world.setShape(b, const NativeShape.sphere(0.1));
      return b;
    }

    final near = ball(1.0);
    final far = ball(-2.0);
    expect(world.explode(Vector3.zero(), const NativeExplosion.tnt(1.0)), 2);
    world.step(0.001);
    final vNear = world.velocityOf(near).x;
    final vFar = world.velocityOf(far).x;
    // Mutation: a push by distance rather than its square.
    expect(vNear, greaterThan(0));
    expect(vNear / -vFar, closeTo(4.0, 0.1));
    expect(
      () => world.explode(
        Vector3.zero(),
        const NativeExplosion(energy: 0.0, mass: 0.0),
      ),
      throwsArgumentError,
    );
  });
}
