/// FXAA: edges smoothed on the finished picture, and a sharpen pass that
/// shares its taps.
///
/// Quoted by `anti_aliasing.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class AntiAliasingDemo extends ShowcaseDemo {
  bool enabled = true;
  double sharpen = 0.0;

  /// One diagonal card staircases at exactly one contrast step, over one
  /// edge — too little for either pass to read as more than noise at a
  /// glance. A dozen thin spokes cross that same centre at a dozen
  /// different angles, so every angle a staircase can take is on screen at
  /// once, and the same handful of pixels near the middle carry all of
  /// them where the effect is easiest to see.
  static const int _spokes = 14;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.5
      ..pitch = 0.0
      ..yaw = 0.0;
  }

  @override
  Scene build(DemoContext context) {
    // #region card
    final DeviceMesh spoke = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(0.1, 2.8, 0.1)).build(),
    );
    final Material material = Material(
      name: 'spokes',
      baseColor: Vector4(0.95, 0.95, 0.95, 1.0),
      lighting: LightingModel.unlit,
    );
    final Scene scene = Scene();
    for (var i = 0; i < _spokes; i++) {
      // Only half a turn: a spoke through the origin looks the same rotated
      // by pi, so a full turn would draw every angle twice.
      final double angle = i / _spokes * math.pi;
      scene.add(
        MeshNode(spoke, material, name: 'spoke $i')
          ..setLocalMatrix(Matrix4.rotationZ(angle)),
      );
    }
    // #endregion card
    return scene;
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    antiAlias: AntiAliasSettings(enabled: enabled, sharpen: sharpen),
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'FXAA',
      value: () => enabled,
      onChanged: (bool v) => enabled = v,
    ),
    SliderControl(
      'Sharpen',
      min: 0,
      max: 1,
      value: () => sharpen,
      onChanged: (double v) => sharpen = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region reported
    final bool ran = frame.antiAliasing.fxaa;
    if (ran != enabled) {
      throw StateError(
        'the frame reports fxaa: $ran while the page asked '
        'for $enabled',
      );
    }
    // #endregion reported
  }
}
