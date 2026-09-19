/// A single burst that lights the room it goes off in, the way a muzzle
/// flash or an explosion should but a burst with nobody keyed to it cannot.
///
/// Quoted by `burst_light.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class _Flash with LightEmitter {}

final class BurstLightDemo extends ShowcaseDemo {
  late final ParticleSystem _particles;
  late final LightNode _glow;

  final _Flash _flash = _Flash();

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.0
      ..pitch = 0.2
      ..yaw = 0.4;
  }

  @override
  Scene build(DemoContext context) {
    _particles = ParticleSystem(capacity: 128, seed: 512);

    // #region source
    // Nothing above this differs from an ordinary burst. `source` is the
    // whole of what makes it a light: a `LightEmitter` passed here has its
    // glow fed by exactly these particles, for as long as they live.
    final ParticleEffect flash = ParticleEffect(
      count: 60,
      emitter: const SphereEmitter(speed: Range(2.0, 5.0)),
      lifetime: const Range(0.2, 0.4),
      size: const Range(0.05, 0.09),
      color: Vector4(1.0, 0.85, 0.5, 1.0),
    );
    _particles.burst(flash, Vector3.zero(), source: _flash);
    // #endregion source

    context.renderer.addContributor(ParticleContributor(_particles));

    _glow = LightNode(name: 'flash', type: LightType.point, intensity: 0.0);
    return Scene()..add(_glow);
  }

  @override
  void update(DemoContext context, double dt) {
    _particles.advance(dt);

    // #region follow
    final ParticleGlow glow = _flash.glow;
    if (glow.located) {
      _glow.setPositionFrom(glow.centre);
      _glow.intensity = glow.power * 0.6;
    }
    // #endregion follow
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_flash.glow.count == 0 || _flash.glow.power <= 0.0) {
      throw StateError('the burst should have lit its own flash');
    }
    // #endregion check
    if (frame.drawCalls < 1) {
      throw StateError('the flash did not reach the frame');
    }
  }
}
