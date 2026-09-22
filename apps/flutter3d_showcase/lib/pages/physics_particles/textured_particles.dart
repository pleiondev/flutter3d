/// A sprite on every billboard instead of the procedural disc, which is what
/// turns a particle into any shape you can paint.
///
/// Quoted by `textured_particles.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class TexturedParticlesDemo extends ShowcaseDemo {
  late final ParticleSystem _particles;
  late final ParticleEffect _sparksEffect;
  late final ParticleContributor _contributor;

  static const int _size = 32;
  static const int _count = 50;

  // The sprite is the whole point of the page; a burst that never repeated
  // would leave nothing wearing it after the first second.
  static const double _pause = 1.0;
  double _cooldown = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.0
      ..pitch = 0.2
      ..yaw = 0.4;
  }

  // #region sprite
  /// A four-pointed spark: bright along the axes, dark at the corners. Not a
  /// shape the procedural disc every untextured particle uses can make.
  ByteData _sparkSprite() {
    final Uint8List bytes = Uint8List(_size * _size * 4);
    for (var y = 0; y < _size; y++) {
      for (var x = 0; x < _size; x++) {
        final double dx = (x + 0.5) / _size * 2.0 - 1.0;
        final double dy = (y + 0.5) / _size * 2.0 - 1.0;
        final double along = math.max(dx.abs(), dy.abs());
        final double across = math.min(dx.abs(), dy.abs());
        final double alpha = (1.0 - along) * (1.0 - across * 3.0);
        final int at = (y * _size + x) * 4;
        bytes[at] = 255;
        bytes[at + 1] = 220;
        bytes[at + 2] = 160;
        bytes[at + 3] = (alpha.clamp(0.0, 1.0) * 255).round();
      }
    }
    return bytes.buffer.asByteData();
  }
  // #endregion sprite

  @override
  Scene build(DemoContext context) {
    // #region texture
    final TextureHandle sprite = context.device.createTextureFromPixels(
      width: _size,
      height: _size,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: _sparkSprite(),
    )!;
    // #endregion texture

    _particles = ParticleSystem(capacity: _count, seed: 909);
    _sparksEffect = ParticleEffect(
      count: _count,
      emitter: const SphereEmitter(speed: Range(1.0, 2.0)),
      lifetime: const Range(0.8, 1.4),
      size: const Range(0.1, 0.16),
      color: Vector4(1.0, 1.0, 1.0, 1.0),
    );
    _particles.burst(_sparksEffect, Vector3.zero());

    // #region contributor
    _contributor = context.renderer.addContributor(
      ParticleContributor(_particles, texture: sprite),
    );
    // #endregion contributor

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
        _particles.burst(_sparksEffect, Vector3.zero());
        _cooldown = _pause;
      }
    }
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_contributor.texture == null) {
      throw StateError('the contributor should be drawing a sprite');
    }
    // #endregion check
    if (_particles.aliveCount != _count || frame.drawCalls < 1) {
      throw StateError('the sparks did not reach the frame');
    }
  }
}
