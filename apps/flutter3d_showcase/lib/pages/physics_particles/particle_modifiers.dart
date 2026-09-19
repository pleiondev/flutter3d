/// What happens to a particle after it is born: gravity, drag, wind,
/// turbulence and spin, stacked on the same burst.
///
/// Quoted by `particle_modifiers.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ParticleModifiersDemo extends ShowcaseDemo {
  late final ParticleSystem _particles;
  late final ParticleEffect _debrisEffect;
  late final ParticleContributor _contributor;
  late final List<ParticleAffector> _affectors;

  static const int _count = 80;

  // Turbulence and wind are easiest to read while the debris is still
  // moving, not once it has settled and stopped.
  static const double _pause = 1.0;
  double _cooldown = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.5
      ..pitch = 0.25
      ..yaw = 0.4;
  }

  @override
  Scene build(DemoContext context) {
    _particles = ParticleSystem(capacity: _count, seed: 90210);

    // #region affectors
    _affectors = <ParticleAffector>[
      const ParticleGravity(-4.0),
      const ParticleDrag(0.4),
      ParticleWind(Vector3(0.6, 0.0, 0.0)),
      const ParticleTurbulence(strength: 1.5, scale: 0.8),
      const ParticleSpin(turnsPerSecond: 1.2),
    ];
    // #endregion affectors

    // #region effect
    _debrisEffect = ParticleEffect(
      count: _count,
      emitter: const ConeEmitter(speed: Range(1.5, 3.0), halfAngleDegrees: 30),
      lifetime: const Range(1.5, 2.5),
      size: const Range(0.06, 0.1),
      color: Vector4(0.9, 0.6, 0.3, 1.0),
      affectors: _affectors,
    );
    // #endregion effect

    // #region burst
    _particles.burst(
      _debrisEffect,
      Vector3.zero(),
      direction: Vector3(0.0, 1.0, 0.0),
    );
    _contributor = context.renderer.addContributor(
      ParticleContributor(_particles),
    );
    // #endregion burst

    return Scene()..add(
      LightNode(name: 'sun', intensity: 2.0)
        ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
    );
  }

  @override
  void update(DemoContext context, double dt) {
    // #region advance
    _particles.advance(dt);
    // #endregion advance

    if (_particles.aliveCount == 0) {
      _cooldown -= dt;
      if (_cooldown <= 0.0) {
        _particles.burst(
          _debrisEffect,
          Vector3.zero(),
          direction: Vector3(0.0, 1.0, 0.0),
        );
        _cooldown = _pause;
      }
    }
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (_particles.aliveCount != _count) {
      throw StateError('expected $_count live particles');
    }
    if (!_contributor.isActive || frame.drawCalls < 1) {
      throw StateError('the burst did not reach the frame');
    }

    // #region check
    // The system keeps no public handle on one particle, so the claim is
    // checked the way the affectors are unit tested: run the same list
    // against a particle of our own and read what changed.
    final Particle sample = Particle()
      ..velocity.setValues(0.0, 2.0, 0.0)
      ..age = 0.4
      ..lifetime = 2.0
      ..seed = 0.5;
    for (final ParticleAffector affector in _affectors) {
      affector.apply(sample, 1 / 60);
    }
    if (sample.velocity.y >= 2.0) {
      throw StateError('gravity and drag should have slowed the climb');
    }
    if (sample.rotation == 0.0) {
      throw StateError('spin should have turned the particle');
    }
    // #endregion check
  }
}
