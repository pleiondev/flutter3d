/// A liquid at its temperature: what floats and sinks in it is lifted and
/// dragged by its density and viscosity there, and under the accurate
/// profile the push is the velocity's own equation through the step.
///
///     dart test test/fluid/liquid_state_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

RevolvedVessel _vat(double r, double h) =>
    RevolvedVessel([Vector2(0, 0), Vector2(r, 0), Vector2(r, h)]);

const double _r = 0.001;

/// A steel ball of radius [_r] let go in a vat of glycerol at [state],
/// after [steps] fluid steps of [step] seconds: its vertical velocity.
double _settle({
  MaterialState? state,
  SimulationProfile profile = SimulationProfile.deterministic,
  int steps = 2000,
  double step = 1 / 2000,
}) {
  final gravity = Vector3(0, -9.81, 0);
  final collisions = CollisionWorld();
  final dynamics = Dynamics(
    world: collisions,
    gravity: gravity,
    profile: profile,
  );
  final ball = dynamics.add(
    RigidBody(
      world: collisions,
      shape: CollisionSphere(_r),
      position: Vector3(0, 0.25, 0),
      mass: 7800 * 4 / 3 * math.pi * _r * _r * _r,
    ),
  );
  final world = FluidWorld(gravity: gravity, step: step, profile: profile);
  final vat = LiquidBody(
    shape: _vat(0.05, 0.4),
    medium: FluidMedium.glycerol,
    volume: math.pi * 0.0025 * 0.3,
    modes: 2,
  )..state = state;
  world.bodies.add(vat);
  world.float(ball);
  for (var i = 0; i < steps; i++) {
    vat.place(Matrix3.identity(), Vector3.zero());
    world.advance(world.step);
    dynamics.step(world.step);
  }
  return ball.velocity.y;
}

void main() {
  test("a catalogue liquid at its reference state is the catalogue's", () {
    for (final medium in <FluidMedium>[
      FluidMedium.water,
      FluidMedium.glycerol,
      FluidMedium.mercury,
    ]) {
      final at = medium.at(MaterialState.standard);
      expect(at.density, medium.density);
      expect(at.viscosity, medium.viscosity);
      expect(at.surfaceTension, medium.surfaceTension);
    }
  });

  test('warm water is lighter and thinner; numbers given are numbers kept', () {
    final hot = FluidMedium.water.at(MaterialState.at(temperature: 333.15));
    expect(hot.density, lessThan(FluidMedium.water.density));
    expect(hot.viscosity, lessThan(0.5 * FluidMedium.water.viscosity));
    // A medium given as numbers has no laws to read.
    final given = FluidMedium.water.copyWith(viscosity: 0.002);
    expect(given.material, isNull);
    expect(given.at(MaterialState.at(temperature: 333.15)), same(given));
  });

  test('a ball sinks through warm glycerol as its viscosity there says', () {
    // Mutation: buoy and drag by the medium as quoted, not at the liquid's
    // state, and the two speeds are one.
    final cold = _settle(state: MaterialState.standard);
    final warm = _settle(state: MaterialState.at(temperature: 313.15));
    final hot = FluidMedium.glycerol.at(MaterialState.at(temperature: 313.15));
    final stokes = stokesSpeed(hot, _r, 7800, 9.81);
    // Stokes's speed at 40 °C, where Re reaches 0.4 and White's correlation
    // adds a few per cent of drag.
    expect(-warm, closeTo(stokes, stokes * 0.1));
    expect(warm / cold, greaterThan(4.0));
  });

  test('a liquid with no state pushes to the bits it did', () {
    expect(_settle(steps: 200), _settle(steps: 200, state: null));
    expect(
      _settle(steps: 200),
      _settle(steps: 200, state: MaterialState.standard),
    );
  });

  test('under the accurate profile the push does not depend on the step', () {
    // Mutation: push under the accurate profile with the implicit step, and
    // halving the step moves the answer by the implicit step's own error.
    final coarse = _settle(
      profile: SimulationProfile.accurate,
      steps: 6,
      step: 1 / 2000,
    );
    final fine = _settle(
      profile: SimulationProfile.accurate,
      steps: 12,
      step: 1 / 4000,
    );
    expect(fine, closeTo(coarse, 1e-6 * coarse.abs()));
    final fixedCoarse = _settle(steps: 6, step: 1 / 2000);
    final fixedFine = _settle(steps: 12, step: 1 / 4000);
    expect((fixedFine - fixedCoarse).abs(), greaterThan(1e-3 * coarse.abs()));
  });
}
