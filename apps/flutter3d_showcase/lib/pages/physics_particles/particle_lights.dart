/// A torch whose flame lights the room it burns in, measured from the
/// particles themselves rather than from a light somebody hand-tuned to
/// match.
///
/// Quoted by `particle_lights.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

/// Mixing in [LightEmitter] is the whole of what it takes to become a source
/// the particle system will measure. It carries no fields of its own.
final class _Torch with LightEmitter {}

final class ParticleLightsDemo extends ShowcaseDemo {
  late final ParticleSystem _particles;
  late final LightNode _glow;

  final _Torch _torch = _Torch();

  static const double _rate = 240.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.0
      ..pitch = 0.2
      ..yaw = 0.4;
  }

  @override
  Scene build(DemoContext context) {
    _particles = ParticleSystem(capacity: 256, seed: 77);

    // #region emit
    final ParticleEffect flame = ParticleEffect(
      count: 1,
      emitter: const ConeEmitter(speed: Range(0.8, 1.6), halfAngleDegrees: 12),
      lifetime: const Range(0.4, 0.7),
      size: const Range(0.08, 0.14),
      color: Vector4(1.0, 0.6, 0.2, 1.0),
      affectors: <ParticleAffector>[const ParticleFade(startsAt: 0.3)],
    );
    _particles.emit(
      _torch,
      flame,
      Vector3.zero(),
      perSecond: _rate,
      direction: Vector3(0.0, 1.0, 0.0),
    );
    // #endregion emit

    context.renderer.addContributor(ParticleContributor(_particles));

    // #region light
    _glow = LightNode(name: 'glow', type: LightType.point, intensity: 0.0);
    // #endregion light

    return Scene()..add(_glow);
  }

  @override
  void update(DemoContext context, double dt) {
    // #region advance
    _particles.advance(dt);
    // #endregion advance

    // #region follow
    final ParticleGlow glow = _torch.glow;
    if (glow.located) {
      _glow.setPositionFrom(glow.centre);
      _glow.intensity = glow.power * 0.6;
    }
    // #endregion follow
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_torch.glow.count == 0 || _torch.glow.power <= 0.0) {
      throw StateError('the torch should be lit by its own flame');
    }
    // #endregion check
    if (frame.drawCalls < 1) {
      throw StateError('the flame did not reach the frame');
    }
  }
}
