/// Four emitter shapes, each bursting from its own spot so the difference
/// between them is something you can see rather than something you are told.
///
/// Quoted by `particle_emitters.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ParticleEmittersDemo extends ShowcaseDemo {
  late final ParticleSystem _particles;
  late final ParticleContributor _contributor;

  static const int _perBurst = 40;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.0
      ..pitch = 0.25
      ..yaw = 0.5;
  }

  ParticleEffect _effect(ParticleEmitter emitter) => ParticleEffect(
    count: _perBurst,
    emitter: emitter,
    lifetime: const Range(0.6, 1.2),
    size: const Range(0.05, 0.09),
    color: Vector4(0.8, 0.85, 1.0, 1.0),
  );

  @override
  Scene build(DemoContext context) {
    _particles = ParticleSystem(capacity: _perBurst * 4, seed: 314159);

    // #region shapes
    // A sphere throws particles outwards in every direction: an explosion.
    // A cone narrows that spread around one axis: a muzzle flash, sparks off
    // a wall. A box fills a volume rather than starting at a point: rain over
    // an area. A drift barely moves outward at all: smoke.
    final List<(Vector3, ParticleEmitter)> shapes =
        <(Vector3, ParticleEmitter)>[
          (
            Vector3(-3.0, 0.0, 0.0),
            const SphereEmitter(speed: Range(1.0, 2.5)),
          ),
          (
            Vector3(-1.0, 0.0, 0.0),
            const ConeEmitter(speed: Range(2.0, 4.0), halfAngleDegrees: 18.0),
          ),
          (
            Vector3(1.0, 0.0, 0.0),
            // #region along
            BoxEmitter(
              halfExtents: Vector3(0.6, 0.05, 0.6),
              speed: const Range(0.3, 0.6),
              along: Vector3(0, 1, 0),
            ),
            // #endregion along
          ),
          (Vector3(3.0, 0.0, 0.0), const DriftEmitter()),
        ];
    // #endregion shapes

    // #region burst
    for (final (Vector3 origin, ParticleEmitter emitter) in shapes) {
      _particles.burst(
        _effect(emitter),
        origin,
        direction: Vector3(0.0, 1.0, 0.0),
      );
    }
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
    _particles.advance(dt);
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_particles.aliveCount != _perBurst * 4) {
      throw StateError(
        'expected ${_perBurst * 4} particles from four emitters, '
        'got ${_particles.aliveCount}',
      );
    }
    if (!_contributor.isActive || frame.drawCalls < 1) {
      throw StateError('the emitters did not reach the frame');
    }
    // #endregion check
  }
}
