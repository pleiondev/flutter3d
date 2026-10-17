/// A material's loss factor in both cores' contacts: a drop and a head-on
/// pair built once through `RigidDynamics`, stepped by the reference and by
/// the core, and held to one another and to the damped spring's restitution
/// (`restitutionOfLossFactor`) in a world that is not bit-exact; and, under
/// the deterministic profile, the core stepping a world of lossy materials
/// to the very bytes it steps the same world without them.
///
///     dart test test/impact_loss_parity_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A made-up solid of loss factor [eta] and no other number.
PhysicalMaterial _lossy(double eta) => PhysicalMaterial(
  id: 'test.lossy$eta',
  name: 'lossy',
  phase: MaterialPhase.solid,
  inelastic: InelasticProperties(
    lossFactor: ConstantLaw(eta),
    source: 'made up for the test',
  ),
);

/// A world of [profile] in a vacuum, as the reference has no air.
CollisionWorld _world(SimulationProfile profile, {Vector3? gravity}) =>
    CollisionWorld()
      ..properties = WorldProperties(
        profile: profile,
        airDensity: 1e-30,
        gravity: gravity,
      );

/// What a scene measured: the speed out of its contact over the speed in,
/// and the native core's snapshot at the end where it ran on the core.
typedef _Measured = ({double ratio, List<int>? bytes});

/// A scene: built on a world through `RigidDynamics`, stepped, measured.
typedef _Scene =
    _Measured Function(
      RigidDynamics Function(CollisionWorld world) make,
      SimulationProfile profile, {
      required bool lossy,
    });

List<int>? _bytesOf(RigidDynamics dynamics) =>
    dynamics is NativeDynamics ? dynamics.native.snapshot() : null;

/// A ball of restitution 0.9 dropped from two metres on a floor of η = 0.4
/// (with [lossy]; of nothing in particular without).
_Measured _drop(
  RigidDynamics Function(CollisionWorld world) make,
  SimulationProfile profile, {
  required bool lossy,
}) {
  final world = _world(profile)
    ..add(
      Collider(
        shape: CollisionBox(Vector3(20.0, 0.5, 20.0)),
        position: Vector3(0.0, -0.5, 0.0),
        material: lossy ? _lossy(0.4) : null,
      ),
    )
    ..update();
  final dynamics = make(world);
  final ball = dynamics.add(
    RigidBody(
      world: world,
      shape: CollisionSphere(0.25),
      position: Vector3(0.0, 2.25, 0.0),
      mass: 1.0,
      restitution: 0.9,
    ),
  );
  var down = 0.0, up = 0.0;
  for (var i = 0; i < 120; i++) {
    dynamics.step(_dt);
    world
      ..update()
      ..clearKinematicDeltas();
    down = math.max(down, -ball.velocity.y);
    up = math.max(up, ball.velocity.y);
  }
  return (ratio: up / down, bytes: _bytesOf(dynamics));
}

/// Two balls of a kilogram and restitution 0.9 head on with no gravity,
/// the left one of η = 0.4 (with [lossy]): how fast they part over how
/// fast they met.
_Measured _headOn(
  RigidDynamics Function(CollisionWorld world) make,
  SimulationProfile profile, {
  required bool lossy,
}) {
  final world = _world(profile, gravity: Vector3.zero());
  final dynamics = make(world);
  RigidBody ball(double x, double vx, PhysicalMaterial? material) =>
      dynamics.add(
        RigidBody(
          world: world,
          shape: CollisionSphere(0.25),
          position: Vector3(x, 0.0, 0.0),
          mass: 1.0,
          restitution: 0.9,
          material: material,
        )..velocity.setValues(vx, 0.0, 0.0),
      );
  final a = ball(-1.0, 3.0, lossy ? _lossy(0.4) : null);
  final b = ball(1.0, -1.0, null);
  for (var i = 0; i < 60; i++) {
    dynamics.step(_dt);
    world
      ..update()
      ..clearKinematicDeltas();
  }
  // Momentum is kept on both, so the parting speed says the restitution.
  return (
    ratio: (b.velocity.x - a.velocity.x) / 4.0,
    bytes: _bytesOf(dynamics),
  );
}

void main() {
  RigidDynamics reference(CollisionWorld world) =>
      Dynamics(world: world)..sleepAfter = double.infinity;
  RigidDynamics core(CollisionWorld world) {
    final dynamics = NativeDynamics(world: world);
    dynamics.native.setSleep(speed: 0.0, time: 0.0);
    addTearDown(dynamics.dispose);
    return dynamics;
  }

  final damped = restitutionOfLossFactor(0.4);
  for (final (name, scene) in <(String, _Scene)>[
    ('a ball dropped on a lossy floor', _drop),
    ('two balls head on, one lossy', _headOn),
  ]) {
    group(name, () {
      test('in a world that is not bit-exact, both cores damp it to the '
          "spring's restitution", () {
        // Mutation: leave the loss factor out of the core's contact (or out
        // of NativeDynamics), and the core bounces at 0.9 while the
        // reference bounces at 0.53.
        const accurate = SimulationProfile.accurate;
        final r = scene(reference, accurate, lossy: true);
        final n = scene(core, accurate, lossy: true);
        // The two step apart, the reference in doubles in one step, the
        // core in floats in substeps; each measures the speed at a step's
        // end, a step's gravity off the contact's. Three hundredths holds
        // both to the law and to each other.
        expect(r.ratio, closeTo(damped, 0.03));
        expect(n.ratio, closeTo(damped, 0.03));
        expect(n.ratio, closeTo(r.ratio, 0.03));
        // And without a loss factor, both bounce at the 0.9 they were given.
        expect(
          scene(reference, accurate, lossy: false).ratio,
          greaterThan(0.85),
        );
        expect(scene(core, accurate, lossy: false).ratio, greaterThan(0.85));
      });

      test('under the deterministic profile the core steps to the same bytes '
          'as without the loss factor', () {
        // Mutation: give the core the loss factors whatever the world's
        // profile. The bounce then changes, and the C digests and every tape
        // recorded on the core with them.
        const deterministic = SimulationProfile.deterministic;
        final plain = scene(core, deterministic, lossy: false);
        final lossy = scene(core, deterministic, lossy: true);
        expect(lossy.ratio, greaterThan(0.85));
        expect(lossy.bytes, plain.bytes);
        expect(
          scene(reference, deterministic, lossy: true).ratio,
          scene(reference, deterministic, lossy: false).ratio,
        );
      });
    });
  }
}
