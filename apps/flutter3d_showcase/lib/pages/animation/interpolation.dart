/// Three cubes bounce on the same keyframes through three different
/// `AnimationInterpolation`s: step, linear and cubic spline.
///
/// Quoted by `interpolation.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class InterpolationDemo extends ShowcaseDemo {
  late final AnimationPlayer _player;
  late final MeshNode _stepCube;
  late final MeshNode _linearCube;
  late final MeshNode _cubicCube;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.5
      ..pitch = 0.2;
  }

  @override
  Scene build(DemoContext context) {
    final DeviceMesh box = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3.all(0.6)).build(),
    );
    _stepCube = MeshNode(
      box,
      Material(name: 'step', baseColor: Vector4(0.85, 0.25, 0.2, 1.0)),
      name: 'step',
    );
    _linearCube = MeshNode(
      box,
      Material(name: 'linear', baseColor: Vector4(0.25, 0.75, 0.3, 1.0)),
      name: 'linear',
    );
    _cubicCube = MeshNode(
      box,
      Material(name: 'cubic', baseColor: Vector4(0.25, 0.4, 0.9, 1.0)),
      name: 'cubic',
    );

    // #region tracks
    // The player writes a translation track's sampled (x, y, z) straight
    // through `setPosition`, replacing whatever was there — so the column
    // each cube stands in has to be baked into the track itself. A
    // `setPosition` on the node instead would have held for exactly one
    // frame, until `AnimationPlayer.play` below sampled time zero and
    // snapped every cube back to x = 0, stacking all three on top of each
    // other.
    final AnimationTrack stepTrack = _bounceTrack(
      nodeIndex: 0,
      x: -1.4,
      interpolation: AnimationInterpolation.step,
    );
    final AnimationTrack linearTrack = _bounceTrack(
      nodeIndex: 1,
      x: 0.0,
      interpolation: AnimationInterpolation.linear,
    );
    final AnimationTrack cubicTrack = _bounceTrack(
      nodeIndex: 2,
      x: 1.4,
      interpolation: AnimationInterpolation.cubicSpline,
    );
    // #endregion tracks

    // #region player
    final AnimationClip bounce = AnimationClip(
      name: 'bounce',
      tracks: <AnimationTrack>[stepTrack, linearTrack, cubicTrack],
    );
    _player = AnimationPlayer(
      clips: <AnimationClip>[bounce],
      targets: <AnimationTarget?>[_stepCube, _linearCube, _cubicCube],
    )..play(0);
    // #endregion player

    return Scene()
      ..add(_stepCube)
      ..add(_linearCube)
      ..add(_cubicCube)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.3, -0.8, -0.4)),
      );
  }

  /// The same three keys, up and back down, on every track: only how the
  /// player reads *between* them changes.
  ///
  /// A cubic key carries an in tangent, the value and an out tangent; flat
  /// tangents (zero) are enough to show the ease the other two do not have.
  static AnimationTrack _bounceTrack({
    required int nodeIndex,
    required double x,
    required AnimationInterpolation interpolation,
  }) {
    final Float32List times = Float32List.fromList(<double>[0.0, 0.5, 1.0]);
    final List<double> heights = <double>[0.0, 1.4, 0.0];
    final int perKey = interpolation.valuesPerKey;
    final Float32List values = Float32List(heights.length * 3 * perKey);

    for (var i = 0; i < heights.length; i++) {
      final int base = i * 3 * perKey;
      // For a cubic key the value sits in the middle third; the in and out
      // tangent thirds stay zero, which is a flat tangent — including x's,
      // since it never moves and a flat tangent is what "never moves" means.
      final int valueAt = base + (perKey == 3 ? 3 : 0);
      values[valueAt] = x;
      values[valueAt + 1] = heights[i];
    }

    return AnimationTrack(
      nodeIndex: nodeIndex,
      path: AnimationPath.translation,
      interpolation: interpolation,
      times: times,
      values: values,
      componentCount: 3,
    );
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _player.update(dt);
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Speed',
      min: 0.1,
      max: 2,
      value: () => _player.speed,
      onChanged: (double v) => _player.speed = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final Vector3 step = _stepCube.worldMatrix.getTranslation();
    final Vector3 linear = _linearCube.worldMatrix.getTranslation();
    final Vector3 cubic = _cubicCube.worldMatrix.getTranslation();

    // Each track's baked x must survive the player writing translation
    // through — a track that forgot it would snap every cube to x = 0 and
    // stack the three on top of each other.
    if ((step.x - -1.4).abs() > 1e-6 ||
        linear.x.abs() > 1e-6 ||
        (cubic.x - 1.4).abs() > 1e-6) {
      throw StateError(
        'the three cubes should stand apart at x = -1.4, 0, 1.4; got '
        '${step.x}, ${linear.x}, ${cubic.x}',
      );
    }
    if (step.y.abs() > 1e-6) {
      throw StateError('step should hold the first key until the next one');
    }
    if (linear.y <= 1e-4) {
      throw StateError('linear should already have left the first key');
    }
    if (cubic.y <= 0.0 || cubic.y >= linear.y) {
      throw StateError(
        'cubic should ease away from the first key slower than linear does',
      );
    }
  }
}
