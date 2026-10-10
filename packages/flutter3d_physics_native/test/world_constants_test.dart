/// A world's gravity and air are the world's, and what lives in it reads
/// them there.
///
///     dart test test/world_constants_test.dart
///
/// Two halves. A new world is the standard one — the core's own defaults
/// and `standard_world.dart`'s are the same numbers, to the bit the core
/// keeps — and the doubles a consumer reads back are the ones it used to
/// write, so nothing recorded under 9.81 moves. And a world set on the
/// Moon is the Moon for what is made in it: a spray, a cloth, a tank, a
/// heap of debris.
library;

import 'dart:typed_data';

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// [x] as the core keeps it, in f32.
double _f32(double x) => (Float32List(1)..[0] = x)[0];

void main() {
  late NativeWorld world;
  setUp(() => world = NativeWorld());
  tearDown(() => world.dispose());

  test('a new world is the standard world, as the core keeps it', () {
    // Mutation: change f3d_world_create's gravity to F3D_R(-9.80665) — fails
    // because the core and standard_world.dart then disagree, and every
    // consumer that read 9.81 from the Dart side would fall differently
    // from the bodies the core steps beside it.
    expect(world.gravity, standardGravityVector);
    expect(world.airTemperature, _f32(standardAirTemperature));
    expect(world.airDensity, _f32(standardAirDensity));
    expect(world.airPressure, standardAtmosphere);
  });

  test('a standard world\'s gravity reads back as the double it was', () {
    // Mutation: drop the standard branch of gravityMagnitude and return the
    // length of what the core holds — fails because that is
    // 9.8100004196…, and a weir, a depth gauge or an ember that wrote 9.81
    // before it read its world would move by four parts in 10⁸, and every
    // tape and golden made under 9.81 with it.
    expect(world.gravityMagnitude, standardGravity);
    expect(identical(world.gravityMagnitude, 9.81), isTrue);

    // Pointed another way, the same strength is its length, no special case.
    world.gravity = Vector3(0.0, 0.0, -standardGravity);
    expect(world.gravityMagnitude, closeTo(standardGravity, 1e-6));
    expect(world.gravityMagnitude, isNot(standardGravity));
  });

  test('on the Moon, what is made in the world falls as the world does', () {
    world.gravity = Vector3(0.0, -1.62, 0.0);
    expect(world.gravityMagnitude, closeTo(1.62, 1e-6));

    // Mutation: drop `world?.gravity` from any one of these defaults —
    // fails because that one falls at 9.81 on the Moon.
    final moon = _f32(-1.62);
    expect(CoreClothSettings(world: world).gravity.y, moon);
    expect(
      FluidSettings(
        tankMin: Vector3.zero(),
        tankMax: Vector3.all(1.0),
        world: world,
      ).gravity.y,
      moon,
    );
    expect(ParticleForces(world: world).gravity.y, moon);
    expect(DebrisSettings(world: world).gravity.y, moon);

    // Without a world, the standard one; an explicit gravity wins over both.
    expect(CoreClothSettings().gravity, standardGravityVector);
    expect(
      ParticleForces(world: world, gravity: Vector3.zero()).gravity,
      Vector3.zero(),
    );

    // And through the core: a spark dropped for one second of 60 steps falls
    // by the Moon's ½gt², not the Earth's.
    final sparks = NativeParticles(1)
      ..emit(<NativeParticle>[
        (position: Vector3.zero(), velocity: Vector3.zero(), life: 10.0),
      ])
      ..step(ParticleForces(world: world), 1.0 / 60.0, steps: 60);
    final y = sparks.read()[1];
    sparks.dispose();
    expect(y, inInclusiveRange(-0.5 * 1.62 * 1.05, -0.5 * 1.62 * 0.95));
  });

  test('water poured at the air\'s temperature takes the world\'s', () {
    world.setAir(temperature: 250.0, density: 1.3);
    final heat = NativeLiquidHeat.water().at(world.airTemperature);
    expect(heat.temperature, 250.0);
    expect(heat.specificHeat, NativeLiquidHeat.water().specificHeat);
    expect(heat.boils, isTrue);
  });

  test('the air\'s pressure is the world\'s, and must be one', () {
    world.airPressure = 0.6 * standardAtmosphere;
    expect(world.airPressure, closeTo(60795.0, 1e-9));
    expect(() => world.airPressure = 0.0, throwsArgumentError);
    expect(() => world.airPressure = double.nan, throwsArgumentError);
  });
}
