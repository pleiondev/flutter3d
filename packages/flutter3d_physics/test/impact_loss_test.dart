/// A material's loss factor in the contact: what a damped spring's
/// restitution takes from a bounce in a world whose profile is not
/// bit-exact, and nothing at all under the deterministic one.
///
///     dart test test/impact_loss_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
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

/// A ball of restitution [restitution] made of [ball], dropped from two
/// metres onto a floor made of [floor], in a world of [profile]: the
/// fastest it leaves the floor over the fastest it met it, and every
/// position it passed through.
({double ratio, List<double> heights}) _drop({
  required SimulationProfile profile,
  double restitution = 0.9,
  PhysicalMaterial? ball,
  PhysicalMaterial? floor,
}) {
  final world = CollisionWorld()
    ..properties = WorldProperties(profile: profile)
    ..add(
      Collider(
        shape: CollisionBox(Vector3(20.0, 0.5, 20.0)),
        position: Vector3(0.0, -0.5, 0.0),
        material: floor,
      ),
    )
    ..update();
  final dynamics = Dynamics(world: world)..sleepAfter = double.infinity;
  final body = dynamics.add(
    RigidBody(
      world: world,
      shape: CollisionSphere(0.25),
      position: Vector3(0.0, 2.25, 0.0),
      mass: 1.0,
      restitution: restitution,
      material: ball,
    ),
  );
  var down = 0.0, up = 0.0;
  final heights = <double>[];
  for (var i = 0; i < 120; i++) {
    dynamics.step(_dt);
    world
      ..update()
      ..clearKinematicDeltas();
    down = math.max(down, -body.velocity.y);
    up = math.max(up, body.velocity.y);
    heights.add(body.position.y);
  }
  return (ratio: up / down, heights: heights);
}

void main() {
  test('the loss factor gives the restitution of a damped spring', () {
    // Mutation: take ζ as η rather than η/2, and a rubber of η = 0.4 comes
    // back at 0.26 instead of 0.53.
    expect(restitutionOfLossFactor(0.0), 1.0);
    expect(restitutionOfLossFactor(0.4), closeTo(0.5266, 1e-4));
    // Small, it is 1 − πζ to first order.
    expect(restitutionOfLossFactor(1e-4), closeTo(1.0 - math.pi * 5e-5, 1e-7));
    expect(restitutionOfLossFactor(2.0), 0.0);
    expect(restitutionOfLossFactor(2.5), 0.0);
    expect(() => restitutionOfLossFactor(-0.1), throwsArgumentError);
    expect(() => restitutionOfLossFactor(double.nan), throwsArgumentError);
  });

  test('in a world that is not bit-exact, the lossier side takes from the '
      'bounce', () {
    // Mutation: leave the loss factor out of the contact. The ball then
    // comes back at its own 0.9 whatever it lands on.
    const accurate = SimulationProfile.accurate;
    // The fall as a ball of the damped spring's restitution makes it, to
    // the bit: the loss factor is that restitution and nothing else.
    final damped = _drop(
      profile: accurate,
      restitution: restitutionOfLossFactor(0.4),
    );
    expect(damped.ratio, closeTo(0.5266, 0.03));
    for (final (ball, floor) in <(double?, double?)>[
      (0.4, null),
      (null, 0.4),
      (0.1, 0.4),
    ]) {
      final fall = _drop(
        profile: accurate,
        ball: ball == null ? null : _lossy(ball),
        floor: floor == null ? null : _lossy(floor),
      );
      expect(fall.heights, damped.heights, reason: 'ball $ball, floor $floor');
    }
    // A loss factor only takes away: a steel's 1e-4 leaves a half a half.
    expect(
      _drop(profile: accurate, restitution: 0.5, ball: _lossy(1e-4)).heights,
      _drop(profile: accurate, restitution: 0.5).heights,
    );
    expect(_drop(profile: accurate).ratio, greaterThan(0.85));
  });

  test('under the deterministic profile nothing moves', () {
    // Mutation: damp whatever the profile. A game's tapes, recorded with a
    // rubber ball, then replay to other bits.
    const deterministic = SimulationProfile.deterministic;
    final plain = _drop(profile: deterministic);
    final rubber = _drop(
      profile: deterministic,
      ball: _lossy(0.4),
      floor: _lossy(0.4),
    );
    expect(rubber.ratio, greaterThan(0.85));
    expect(rubber.heights, plain.heights);
  });
}
