/// Volumetric fog: air with a thickness that the lights shine through, so
/// each lamp glows in the air around it.
///
/// Quoted by `volumetric_fog.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class VolumetricFogDemo extends ShowcaseDemo {
  bool fog = true;
  bool litByLamps = true;
  double density = 0.3;
  double heightFalloff = 1.0;

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
    // #region torches
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
    for (var i = 0; i < 8; i++) {
      for (var j = 0; j < 8; j++) {
        scene.add(
          LightNode(
            name: 'torch $i $j',
            type: LightType.point,
            intensity: 1.0,
            range: 1.0,
            color: _hue((i * 8 + j) / 64.0),
          )..setPosition(i - 3.5, 0.3, j - 3.5),
        );
      }
    }
    // #endregion torches
    return scene;
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region cells
    clusteredLights: litByLamps,
    // #endregion cells
    // #region fog
    volumetricFog: VolumetricFogSettings(
      enabled: fog,
      density: density,
      heightFalloff: heightFalloff,
      steps: 16,
      distance: 20.0,
      color: Vector3.all(1.0),
    ),
    // #endregion fog
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Volumetric fog',
      value: () => fog,
      onChanged: (bool v) => fog = v,
    ),
    ToggleControl(
      'Clustered lights',
      value: () => litByLamps,
      onChanged: (bool v) => litByLamps = v,
    ),
    SliderControl(
      'Density',
      min: 0,
      max: 0.8,
      value: () => density,
      onChanged: (double v) => density = v,
      format: (double v) => '${v.toStringAsFixed(2)} per m',
    ),
    SliderControl(
      'Height falloff',
      min: 0,
      max: 3,
      value: () => heightFalloff,
      onChanged: (double v) => heightFalloff = v,
      format: (double v) => '${v.toStringAsFixed(2)} per m',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final PassSkip? skipped = frame.skipReasonOf('volumetric fog');
    if (skipped != null) {
      throw StateError('the fog pass was skipped: $skipped');
    }
    if (!frame.passes.any((FramePass p) => p.name == 'volumetric fog')) {
      throw StateError('the fog pass did not run');
    }
  }
}
