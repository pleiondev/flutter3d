/// Clustered lights: every fragment is lit by the lights that reach its part
/// of the view, so a floor under sixty-four lamps is lit by all of them.
///
/// Quoted by `clustered_lights.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ClusteredLightsDemo extends ShowcaseDemo {
  bool clustered = true;
  double range = 0.8;

  final List<LightNode> _lights = <LightNode>[];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.8
      ..pitch = 1.15
      ..yaw = 0.0;
  }

  /// A saturated colour at [t] of the way round the hue circle.
  static Vector3 _hue(double t) {
    double channel(double offset) =>
        (0.5 + 0.5 * math.cos(2 * math.pi * (t + offset))).clamp(0.0, 1.0);
    return Vector3(channel(0.0), channel(2 / 3), channel(1 / 3));
  }

  @override
  Scene build(DemoContext context) {
    // #region floor
    final Scene scene = Scene()
      ..ambientIntensity = 0.03
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(12.0, 0.1, 12.0)).build(),
          ),
          Material(name: 'floor', lighting: LightingModel.lambert),
          name: 'floor',
        )..setPosition(0.0, -0.05, 0.0),
      );
    // #endregion floor

    // #region lights
    for (var i = 0; i < 8; i++) {
      for (var j = 0; j < 8; j++) {
        final LightNode light = LightNode(
          name: 'lamp $i $j',
          type: LightType.point,
          intensity: 1.5,
          range: range,
          color: _hue((i * 8 + j) / 64.0),
        )..setPosition(i - 3.5, 0.3, j - 3.5);
        _lights.add(light);
        scene.add(light);
      }
    }
    // #endregion lights
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    for (final LightNode light in _lights) {
      light.range = range;
    }
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    clusteredLights: clustered,
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Clustered lights',
      value: () => clustered,
      onChanged: (bool v) => clustered = v,
    ),
    SliderControl(
      'Light range',
      min: 0.4,
      max: 3.0,
      value: () => range,
      onChanged: (double v) => range = v,
      format: (double v) => '${v.toStringAsFixed(1)} m',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (scene.lights.length != 64) {
      throw StateError('the grid should hold 64 lights');
    }
    if (frame.lightsDropped == 0) {
      throw StateError(
        'the frame fit its lights in the eight slots, so no cells were cut',
      );
    }
  }
}
