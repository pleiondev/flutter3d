/// A sprite sheet played across a particle's life instead of a single
/// static sprite, so a spark can burn out frame by frame rather than only
/// fade.
///
/// Quoted by `flipbook.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class FlipbookDemo extends ShowcaseDemo {
  late final ParticleSystem _particles;
  late final Flipbook _flipbook;

  static const int _cellSize = 16;
  static const int _frames = 4;
  static const int _count = 40;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.0
      ..pitch = 0.2
      ..yaw = 0.4;
  }

  // #region atlas
  /// Four cells in a row, each a solid colour: a stand-in for four drawn
  /// frames of a burning-out spark, from bright to dark.
  ByteData _atlas() {
    const List<List<int>> colours = <List<int>>[
      <int>[255, 255, 220],
      <int>[255, 190, 90],
      <int>[220, 90, 40],
      <int>[60, 20, 10],
    ];
    final Uint8List bytes = Uint8List(_cellSize * _frames * _cellSize * 4);
    final int width = _cellSize * _frames;
    for (var y = 0; y < _cellSize; y++) {
      for (var frame = 0; frame < _frames; frame++) {
        final List<int> colour = colours[frame];
        for (var x = 0; x < _cellSize; x++) {
          final int at = (y * width + frame * _cellSize + x) * 4;
          bytes[at] = colour[0];
          bytes[at + 1] = colour[1];
          bytes[at + 2] = colour[2];
          bytes[at + 3] = 255;
        }
      }
    }
    return bytes.buffer.asByteData();
  }
  // #endregion atlas

  @override
  Scene build(DemoContext context) {
    final TextureHandle atlas = context.device.createTextureFromPixels(
      width: _cellSize * _frames,
      height: _cellSize,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: _atlas(),
    )!;

    // #region flipbook
    _flipbook = Flipbook(columns: _frames, rows: 1);
    // #endregion flipbook

    _particles = ParticleSystem(capacity: _count, seed: 606);
    final ParticleEffect sparks = ParticleEffect(
      count: _count,
      emitter: const ConeEmitter(speed: Range(1.0, 2.2), halfAngleDegrees: 20),
      lifetime: const Range(0.8, 1.2),
      size: const Range(0.09, 0.13),
      color: Vector4(1.0, 1.0, 1.0, 1.0),
    );
    _particles.burst(sparks, Vector3.zero(), direction: Vector3(0.0, 1.0, 0.0));

    context.renderer.addContributor(
      ParticleContributor(_particles, texture: atlas, flipbook: _flipbook),
    );

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
    if (_particles.aliveCount != _count || frame.drawCalls < 1) {
      throw StateError('the sparks did not reach the frame');
    }

    // #region check
    // A particle just born and one about to die should be showing different
    // cells of the sheet: the whole point of a flipbook over a static sprite.
    final Particle newborn = Particle()
      ..age = 0.0
      ..lifetime = 1.0;
    final Particle dying = Particle()
      ..age = 0.99
      ..lifetime = 1.0;
    if (_flipbook.cellFor(newborn).left == _flipbook.cellFor(dying).left) {
      throw StateError('the flipbook should play across a particle\'s life');
    }
    // #endregion check
  }
}
