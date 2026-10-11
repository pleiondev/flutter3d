/// A body thrown into the air under the accurate profile flies the
/// parabola, and with a linear drag the curve the drag's law gives: the
/// analytic answers, to the rounding of the doubles and the integrator's
/// tolerance.
///
///     dart test test/projectile_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A drag of [c] newton-seconds per metre against the velocity.
final class _LinearDrag extends BodyForce {
  const _LinearDrag(this.c);

  final double c;

  @override
  void addForce(BodyForceContext context) =>
      context.add(-c * context.vx, -c * context.vy, -c * context.vz);
}

/// A ball thrown from the origin at 20 m/s and 45 degrees, under
/// [profile], with [forces]; stepped [steps] times.
(Dynamics, RigidBody) _throw(
  SimulationProfile profile, {
  List<BodyForce> forces = const <BodyForce>[],
  int steps = 120,
}) {
  final dynamics = Dynamics(world: CollisionWorld(), profile: profile)
    ..forces.addAll(forces);
  final ball = dynamics.add(
    RigidBody(
      world: dynamics.world,
      shape: CollisionSphere(0.1),
      position: Vector3.zero(),
      mass: 2.0,
    ),
  );
  final speed = 20.0 / math.sqrt2;
  ball.velocity.setValues(speed, speed, 0.0);
  for (var i = 0; i < steps; i++) {
    dynamics.step(_dt);
    dynamics.world.update();
  }
  return (dynamics, ball);
}

void main() {
  // The world's gravity as its f32 vector holds it, and the launch velocity
  // as the body's f32 velocity holds it: the analytic answer is for the
  // numbers the run was given.
  final g = WorldProperties.standard.gravity.y;
  final v0 = Vector3.all(20.0 / math.sqrt2).x;
  const t = 120 * _dt;

  test('under the accurate profile a thrown ball flies the parabola', () {
    final (dynamics, ball) = _throw(SimulationProfile.accurate);
    final s = dynamics.exactStateOf(ball);
    expect(s[0], closeTo(v0 * t, 1e-9));
    expect(s[1], closeTo(v0 * t + 0.5 * g * t * t, 1e-9));
    expect(s[4], closeTo(v0 + g * t, 1e-9));
    // The collider is where the doubles round to.
    expect(ball.position.y, Vector3(0.0, s[1], 0.0).y);
  });

  test('under the deterministic profile it does not, by centimetres', () {
    // Mutation: step the accurate profile as the deterministic one does and
    // the test above fails by these centimetres.
    final (dynamics, ball) = _throw(SimulationProfile.deterministic);
    final miss = ball.position.y - (v0 * t + 0.5 * g * t * t);
    // g·Δt·t / 8 below the parabola, from the core's four substeps.
    expect(miss.abs(), greaterThan(0.01));
  });

  test('with a linear drag, the drag law gives the curve', () {
    const c = 0.5, m = 2.0, k = c / m;
    final (dynamics, ball) = _throw(
      SimulationProfile.accurate,
      forces: const <BodyForce>[_LinearDrag(c)],
    );
    final s = dynamics.exactStateOf(ball);
    final decay = (1.0 - math.exp(-k * t)) / k;
    // x = v₀(1 − e^{−kt})/k; y = (v₀ − g/k)(1 − e^{−kt})/k + g t / k, g
    // the signed vertical gravity.
    expect(s[0], closeTo(v0 * decay, 1e-8));
    expect(s[1], closeTo((v0 - g / k) * decay + g * t / k, 1e-8));
    expect(s[4], closeTo((v0 - g / k) * math.exp(-k * t) + g / k, 1e-8));
  });

  test('a ball given an impulse goes on from what it was given', () {
    final (dynamics, ball) = _throw(SimulationProfile.accurate, steps: 10);
    ball.velocity.setValues(0.0, 0.0, 0.0);
    final y = dynamics.exactStateOf(ball)[1];
    dynamics.step(_dt);
    expect(
      dynamics.exactStateOf(ball)[1],
      closeTo(y + 0.5 * g * _dt * _dt, 1e-12),
    );
  });

  test(
    'a save carries the doubles, and the restored run goes on from them',
    () {
      final (dynamics, ball) = _throw(SimulationProfile.accurate, steps: 30);
      final saved = dynamics.saveState();
      final body = ball.save();
      final before = dynamics.exactStateOf(ball);
      for (var i = 0; i < 30; i++) {
        dynamics.step(_dt);
      }
      final straight = dynamics.exactStateOf(ball);
      ball.restore(body);
      dynamics.restoreState(saved);
      expect(dynamics.exactStateOf(ball), before);
      for (var i = 0; i < 30; i++) {
        dynamics.step(_dt);
      }
      expect(dynamics.exactStateOf(ball), straight);
    },
  );

  test("the deterministic profile's save is what it was", () {
    final (dynamics, _) = _throw(SimulationProfile.deterministic, steps: 5);
    expect((dynamics.saveState()! as Map).keys, <String>['world', 'contacts']);
  });
}
