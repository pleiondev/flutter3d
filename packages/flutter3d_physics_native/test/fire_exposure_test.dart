/// The heat a fire throws onto a person and the harm it does them — P9.
///
///     dart test test/fire_exposure_test.dart
///
/// Modak's point source capped by the soot's σT⁴, and ISO 13571's burn
/// dose: the two laws every game here burns by, held in one place.
library;

import 'dart:math' as math;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  const sigma = stefanBoltzmann;

  test('a flame is a point source from its middle, capped by its soot', () {
    // 300 kW radiated, 5 m off: 300000 / (4π·25), 955 W/m². Mutation: spread
    // it over a hemisphere, 2π — fails because it is twice that.
    expect(
      FireExposure.flux(
        radiant: 3e5,
        sootTemperature: 1200.0,
        distanceSquared: 25.0,
      ),
      closeTo(3e5 / (4.0 * math.pi * 25.0), 1e-9),
    );
    // A centimetre off, and in the flame, the soot's own 117.6 kW/m².
    // Mutation: drop the cap — fails because the sphere's flux runs to
    // 239 MW/m² a centimetre off, and to infinity at nought.
    final soot = sigma * math.pow(1200.0, 4);
    for (final r2 in [1e-4, 0.0]) {
      expect(
        FireExposure.flux(
          radiant: 3e5,
          sootTemperature: 1200.0,
          distanceSquared: r2,
        ),
        closeTo(soot, 1e-6),
      );
    }
    // Mutation: return the cap however little is radiated — fails because a
    // flame radiating nothing heats nothing.
    expect(
      FireExposure.flux(
        radiant: 0.0,
        sootTemperature: 1200.0,
        distanceSquared: 0.0,
      ),
      0.0,
    );
  });

  test('ISO 13571\'s burn dose: none to 2.5 kW/m², then 6.9·q^−1.56 min', () {
    expect(FireExposure.burnDoseRate(FireExposure.harmlessFlux), 0.0);
    expect(FireExposure.burnDoseRate(2600.0), greaterThan(0.0));
    // 10 kW/m²: a second-degree burn in 6.9·10^−1.56 = 0.190 minutes.
    // Mutation: the pain law, 4·q^−1.35, in its place — fails because the
    // burn comes in 0.179 minutes.
    expect(
      FireExposure.burnDoseRate(10000.0),
      closeTo(1.0 / (6.9 * 60.0 * math.pow(10.0, -1.56)), 1e-12),
    );
  });

  test('the flux at a point is every fire\'s, from its flame\'s middle', () {
    final world = NativeWorld();
    addTearDown(world.dispose);
    final stone = world.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
      mass: 10.0,
    );
    world
      ..setShape(stone, const NativeShape.sphere(0.1))
      ..setMaterial(stone, NativeMaterial.stone())
      ..setBurner(stone, NativeBurner.campfire())
      ..step(0.1);
    final fire = world.fires().single;
    final middle = FireExposure.middleOf(fire);
    expect(middle, isNot(fire.at));
    final at = middle + Vector3(3.0, 0.0, 0.0);
    // Mutation: measure from the body's middle, `fire.at` — fails because
    // the flame stands half its reach above it, and the point is further.
    expect(
      FireExposure.fluxAt(world.fires(), at),
      closeTo(fire.radiantShare * fire.power / (4.0 * math.pi * 9.0), 1e-9),
    );
    // Mutation: take the nearest fire only, or the last — fails because two
    // fires heat twice.
    expect(
      FireExposure.fluxAt([fire, fire], at),
      closeTo(2.0 * FireExposure.fluxAt([fire], at), 1e-9),
    );
    expect(FireExposure.fluxAt(const [], at), 0.0);
  });
}
