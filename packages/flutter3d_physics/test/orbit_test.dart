/// A body on an eccentric orbit about an inverse-square pull, under the
/// accurate profile: where Kepler puts it after ten turns, and its energy
/// and angular momentum kept.
///
///     dart test test/orbit_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// GM, m³/s², about the origin.
const double _mu = 1000.0;

/// The pull of a point mass at the origin: −GM m r̂ / r².
final class _Pull extends BodyForce {
  const _Pull();

  @override
  void addForce(BodyForceContext c) {
    final r2 = c.x * c.x + c.y * c.y + c.z * c.z;
    final r = math.sqrt(r2);
    final s = -_mu * c.body.mass / (r2 * r);
    c.add(s * c.x, s * c.y, s * c.z);
  }
}

/// Kepler's answer for an orbit of semi-major axis [a] and eccentricity
/// [e] started at periapsis on +x moving along +y: the position at [t].
(double, double) _kepler(double a, double e, double t) {
  final n = math.sqrt(_mu / (a * a * a));
  final m = n * t;
  var big = m;
  for (var i = 0; i < 50; i++) {
    big -= (big - e * math.sin(big) - m) / (1.0 - e * math.cos(big));
  }
  final b = a * math.sqrt(1.0 - e * e);
  return (a * (math.cos(big) - e), b * math.sin(big));
}

void main() {
  test('ten turns of an orbit end where Kepler says, energy kept', () {
    const a = 10.0, e = 0.5;
    final world = CollisionWorld(
      properties: WorldProperties(gravity: Vector3.zero()),
    );
    final dynamics = Dynamics(world: world, profile: SimulationProfile.accurate)
      ..forces.add(const _Pull());
    final rp = a * (1.0 - e);
    final vp = math.sqrt(_mu * (1.0 + e) / rp);
    final body = dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionSphere(0.1),
        position: Vector3(rp, 0.0, 0.0),
        mass: 3.0,
      ),
    );
    body.velocity.setValues(0.0, vp, 0.0);
    // The run starts from the f32 velocity it was given; Kepler's orbit is
    // the one of exactly vp, so start the doubles there.
    final start = dynamics.exactStateOf(body);
    double energy(List<double> s) =>
        0.5 * (s[3] * s[3] + s[4] * s[4] + s[5] * s[5]) -
        _mu / math.sqrt(s[0] * s[0] + s[1] * s[1] + s[2] * s[2]);
    double momentum(List<double> s) => s[0] * s[4] - s[1] * s[3];
    final period = 2.0 * math.pi * math.sqrt(a * a * a / _mu);
    final steps = (10 * period / _dt).round();
    for (var i = 0; i < steps; i++) {
      dynamics.step(_dt);
    }
    final s = dynamics.exactStateOf(body);
    // Kepler's orbit for the velocity the body actually started with.
    final v = start[4];
    final aActual = 1.0 / (2.0 / rp - v * v / _mu);
    final eActual = 1.0 - rp / aActual;
    final (x, y) = _kepler(aActual, eActual, steps * _dt);
    // A micrometre a turn, on an orbit twenty metres across.
    expect(s[0], closeTo(x, 1e-5));
    expect(s[1], closeTo(y, 1e-5));
    expect(s[2], 0.0);
    // Measured: 1.3e-9 of the energy over the ten turns.
    expect((energy(s) - energy(start)) / energy(start), closeTo(0.0, 1e-8));
    expect(
      (momentum(s) - momentum(start)) / momentum(start),
      closeTo(0.0, 1e-8),
    );
  });

  test('under the deterministic profile the same orbit drifts', () {
    // Mutation: the accurate profile stepped as the deterministic one, a
    // force read once a step, and the orbit above misses Kepler by metres.
    final world = CollisionWorld(
      properties: WorldProperties(gravity: Vector3.zero()),
    );
    final dynamics = Dynamics(world: world)..forces.add(const _Pull());
    const rp = 5.0;
    final body = dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionSphere(0.1),
        position: Vector3(rp, 0.0, 0.0),
        mass: 3.0,
      ),
    );
    body.velocity.setValues(0.0, math.sqrt(_mu * 1.5 / rp), 0.0);
    final period = 2.0 * math.pi * math.sqrt(1000.0 / _mu);
    final steps = (10 * period / _dt).round();
    for (var i = 0; i < steps; i++) {
      dynamics.step(_dt);
    }
    final (x, y) = _kepler(10.0, 0.5, steps * _dt);
    final miss = math.sqrt(
      math.pow(body.position.x - x, 2) + math.pow(body.position.y - y, 2),
    );
    expect(miss, greaterThan(0.1));
  });
}
