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
    )..setPosition(-1.4, 0.0, 0.0);
    _linearCube = MeshNode(
      box,
      Material(name: 'linear', baseColor: Vector4(0.25, 0.75, 0.3, 1.0)),
      name: 'linear',
    )..setPosition(0.0, 0.0, 0.0);
    _cubicCube = MeshNode(
      box,
      Material(name: 'cubic', baseColor: Vector4(0.25, 0.4, 0.9, 1.0)),
      name: 'cubic',
    )..setPosition(1.4, 0.0, 0.0);

    // #region tracks
    final AnimationTrack stepTrack = _bounceTrack(
      nodeIndex: 0,
      interpolation: AnimationInterpolation.step,
    );
    final AnimationTrack linearTrack = _bounceTrack(
      nodeIndex: 1,
      interpolation: AnimationInterpolation.linear,
    );
    final AnimationTrack cubicTrack = _bounceTrack(
      nodeIndex: 2,
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
    required AnimationInterpolation interpolation,
  }) {
    final Float32List times = Float32List.fromList(<double>[0.0, 0.5, 1.0]);
    final List<double> heights = <double>[0.0, 1.4, 0.0];
    final int perKey = interpolation.valuesPerKey;
    final Float32List values = Float32List(heights.length * 3 * perKey);

    for (var i = 0; i < heights.length; i++) {
      final int base = i * 3 * perKey;
      // For a cubic key the value sits in the middle third; the in and out
      // tangent thirds stay zero, which is a flat tangent.
      final int valueAt = base + (perKey == 3 ? 3 : 0);
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
    final double stepY = _stepCube.worldMatrix.getTranslation().y;
    final double linearY = _linearCube.worldMatrix.getTranslation().y;
    final double cubicY = _cubicCube.worldMatrix.getTranslation().y;

    if (stepY.abs() > 1e-6) {
      throw StateError('step should hold the first key until the next one');
    }
    if (linearY <= 1e-4) {
      throw StateError('linear should already have left the first key');
    }
    if (cubicY <= 0.0 || cubicY >= linearY) {
      throw StateError(
        'cubic should ease away from the first key slower than linear does',
      );
    }
  }
}
