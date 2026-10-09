/// Particles in a world: they fall by its gravity and drift on its wind.
///
///     dart test test/particle_world_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_matter/flutter3d_matter.dart'
    show WorldProperties, standardGravity;
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The height of the one particle [gravity] dropped from rest for a second in
/// [world].
double _heightAfterASecond(WorldProperties world, ParticleAffector gravity) {
  final system = ParticleSystem(capacity: 4, seed: 1)..world = world;
  final effect = ParticleEffect(
    count: 1,
    emitter: const SphereEmitter(speed: Range.exact(0.0)),
    lifetime: const Range.exact(5.0),
    size: const Range.exact(0.1),
    color: Vector4(1.0, 1.0, 1.0, 1.0),
    affectors: <ParticleAffector>[gravity],
  );
  system.burst(effect, Vector3(0.0, 10.0, 0.0));
  for (var i = 0; i < 60; i++) {
    system.advance(1.0 / 60.0);
  }
  final out = Float32List(4 * ParticleSystem.floatsPerInstance);
  expect(system.writeInstances(out), 1);
  return out[1];
}

void main() {
  final moon = WorldProperties(gravity: Vector3(0.0, -1.62, 0.0));

  test('a spark falls by the world it is in, on the Moon as on the Earth', () {
    // Mutation: hand the particles `standardGravity` instead of the world's
    // and the Moon's spark falls as far as the Earth's.
    final earth =
        10.0 -
        _heightAfterASecond(WorldProperties.standard, const ParticleGravity());
    final lunar = 10.0 - _heightAfterASecond(moon, const ParticleGravity());
    expect(lunar / earth, closeTo(1.62 / standardGravity, 1e-4));
  });

  test('a fall scaled for the look stays a multiple of the world', () {
    final plain = 10.0 - _heightAfterASecond(moon, const ParticleGravity());
    final quick =
        10.0 -
        _heightAfterASecond(moon, const ParticleGravity.world(scale: 2.0));
    expect(quick / plain, closeTo(2.0, 1e-4));
  });

  test('a look of its own is not the world', () {
    expect(
      _heightAfterASecond(moon, const ParticleGravity(1.0)),
      _heightAfterASecond(WorldProperties.standard, const ParticleGravity(1.0)),
    );
  });

  test("drag carries a particle off on the world's wind", () {
    final particle = Particle()..wind.setValues(4.0, 0.0, 0.0);
    for (var i = 0; i < 600; i++) {
      const ParticleDrag(3.0).apply(particle, 1.0 / 60.0);
    }
    // Mutation: drag towards rest instead of towards the air and it stays
    // where it was.
    expect(particle.velocity.x, closeTo(4.0, 1e-6));
  });

  test('in still air drag slows as it always did, to the bit', () {
    final a = Particle()..velocity.setValues(3.0, -2.0, 1.0);
    final b = Vector3(3.0, -2.0, 1.0);
    const ParticleDrag(1.2).apply(a, 1.0 / 60.0);
    expect(a.velocity, b..scale(const ParticleDrag(1.2).factorOf(1.0 / 60.0)));
  });
}

extension on ParticleDrag {
  // What the affector multiplies a speed by in still air over [dt].
  double factorOf(double dt) {
    final probe = Particle()..velocity.setValues(1.0, 0.0, 0.0);
    apply(probe, dt);
    return probe.velocity.x;
  }
}
