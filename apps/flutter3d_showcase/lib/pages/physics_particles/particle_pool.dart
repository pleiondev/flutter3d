/// One pool of particles, drawn in a single instanced call however many
/// effects are bursting out of it.
///
/// Quoted by `particle_pool.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ParticlePoolDemo extends ShowcaseDemo {
  late final ParticleSystem _particles;
  late final ParticleEffect _sprayEffect;
  late final ParticleContributor _contributor;

  static const int _capacity = 512;
  static const int _burstCount = 120;

  // The point of the page is a pool that outlives any one burst; a burst
  // that never repeated would never show it being reused.
  static const double _pause = 1.0;
  double _cooldown = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.0
      ..pitch = 0.3
      ..yaw = 0.5;
  }

  @override
  Scene build(DemoContext context) {
    // #region system
    // A fixed seed, so the same burst comes out byte for byte on every run.
    // That is what a `ParticleRandom` buys: not randomness, but a stream a
    // particle owns from the moment it is born.
    _particles = ParticleSystem(capacity: _capacity, seed: 20260919);
    // #endregion system

    // #region effect
    _sprayEffect = ParticleEffect(
      count: _burstCount,
      emitter: const SphereEmitter(speed: Range(1.5, 3.0)),
      lifetime: const Range(0.8, 1.6),
      size: const Range(0.05, 0.12),
      color: Vector4(1.0, 0.7, 0.3, 1.0),
    );
    // #endregion effect

    // #region burst
    _particles.burst(_sprayEffect, Vector3.zero());
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
        _particles.burst(_sprayEffect, Vector3.zero());
        _cooldown = _pause;
      }
    }
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_particles.aliveCount != _burstCount) {
      throw StateError(
        'expected $_burstCount live particles, got ${_particles.aliveCount}',
      );
    }
    if (!_contributor.isActive || frame.drawCalls < 1) {
      throw StateError('the pool did not reach the frame');
    }
    // #endregion check
  }
}
