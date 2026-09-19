/// Size and colour described as curves over a particle's life, instead of a
/// pair of affectors that can only ever go from one number to another.
///
/// Quoted by `particle_curves.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ParticleCurvesDemo extends ShowcaseDemo {
  late final ParticleSystem _particles;
  late final ParticleEffect _smokeEffect;
  late final ParticleContributor _contributor;
  late final ParticleCurve _size;
  late final ParticleGradient _color;

  static const int _count = 60;

  // The curve and the gradient are the whole point of this page, and both
  // finish fading to nothing by the end of a particle's life — a burst that
  // never repeated would leave nothing on screen to read them from.
  static const double _pause = 1.0;
  double _cooldown = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.0
      ..pitch = 0.2
      ..yaw = 0.5;
  }

  @override
  Scene build(DemoContext context) {
    _particles = ParticleSystem(capacity: _count, seed: 4242);

    // #region curve
    // Puffs up to one and a half times its birth size by the middle of its
    // life, then shrinks away, easing smoothly through the peak rather than
    // arriving at it with a corner.
    _size = ParticleCurve(<CurveKey>[
      CurveKey(0.0, 0.4, ease: KeyEase.smooth),
      CurveKey(0.5, 1.5, ease: KeyEase.smooth),
      CurveKey(1.0, 0.0),
    ]);
    // #endregion curve

    // #region gradient
    _color = ParticleGradient(<GradientKey>[
      GradientKey(0.0, Vector4(1.0, 0.95, 0.6, 1.0)),
      GradientKey(0.4, Vector4(1.0, 0.4, 0.1, 1.0), ease: KeyEase.smooth),
      GradientKey(1.0, Vector4(0.2, 0.05, 0.05, 0.0)),
    ]);
    // #endregion gradient

    // #region effect
    _smokeEffect = ParticleEffect(
      count: _count,
      emitter: const DriftEmitter(speed: Range(0.4, 0.9)),
      lifetime: const Range(1.2, 2.0),
      size: const Range(0.08, 0.12),
      color: Vector4(1.0, 1.0, 1.0, 1.0),
      affectors: <ParticleAffector>[
        ParticleSizeCurve(_size),
        ParticleColorGradient(_color),
      ],
    );
    // #endregion effect

    _particles.burst(_smokeEffect, Vector3.zero());
    _contributor = context.renderer.addContributor(
      ParticleContributor(_particles),
    );

    return Scene()..add(
      LightNode(name: 'sun', intensity: 2.0)
        ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
    );
  }

  @override
  void update(DemoContext context, double dt) {
    _particles.advance(dt);

    if (_particles.aliveCount == 0) {
      _cooldown -= dt;
      if (_cooldown <= 0.0) {
        _particles.burst(_smokeEffect, Vector3.zero());
        _cooldown = _pause;
      }
    }
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (_particles.aliveCount != _count ||
        !_contributor.isActive ||
        frame.drawCalls < 1) {
      throw StateError('the smoke did not reach the frame');
    }

    // #region check
    // The curve holds its end values outside its keys and rises then falls
    // in between, which is what "puffs up, then shrinks" means as numbers.
    if (_size.sample(0.0) >= _size.sample(0.5) ||
        _size.sample(0.5) <= _size.sample(1.0)) {
      throw StateError('the size curve should rise then fall');
    }
    // The gradient fades to nothing: alpha at the last key is zero.
    final Vector4 end = Vector4.zero();
    _color.sampleInto(end, 1.0);
    if (end.w != 0.0) {
      throw StateError('the gradient should fade to nothing');
    }
    // #endregion check
  }
}
