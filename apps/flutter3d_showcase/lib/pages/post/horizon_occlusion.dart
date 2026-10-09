/// Horizon-based ambient occlusion and screen-space indirect light: the
/// occlusion pass searching for the horizon, and bouncing the light of what
/// it finds.
///
/// Quoted by `horizon_occlusion.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class HorizonOcclusionDemo extends ShowcaseDemo {
  AmbientOcclusionMethod method = AmbientOcclusionMethod.ssil;
  double radius = 0.6;
  double strength = 1.0;
  double thickness = 0.3;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.3
      ..pitch = 0.62
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 0.0, -0.5);
  }

  @override
  Scene build(DemoContext context) {
    final GraphicsDevice device = context.device;
    MeshNode slab(Vector3 size, Vector3 at, Vector4 color, String name) =>
        MeshNode(
          DeviceMesh.upload(device, CuboidShape(size: size).build()),
          RenderMaterial(
            lighting: LightingModel.lambert,
            baseColor: _fromSrgb(color),
          ),
          name: name,
        )..setPositionFrom(at);

    // #region room
    final Vector4 white = Vector4(1.0, 1.0, 1.0, 1.0);
    final Scene scene = Scene()
      ..add(
        slab(Vector3(8.0, 0.1, 8.0), Vector3(0.0, -0.05, 0.0), white, 'floor'),
      )
      ..add(
        slab(
          Vector3(8.0, 2.0, 0.2),
          Vector3(0.0, 1.0, -1.0),
          Vector4(0.9, 0.1, 0.08, 1.0),
          'red wall',
        ),
      )
      ..add(
        slab(Vector3(0.6, 0.6, 0.6), Vector3(0.9, 0.3, -0.5), white, 'block'),
      );
    // #endregion room

    // #region light
    scene.ambientIntensity = 0.3 * Photometric.legacyUnit;
    final LightNode sun =
        LightNode(name: 'sun', intensity: 1.5 * Photometric.legacyUnit)
          ..castsShadow = false
          ..setRotationYawPitchRoll(0.0, -0.6, 0.0);
    // #endregion light
    return scene..add(sun);
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    ambientOcclusion: AmbientOcclusionSettings(
      enabled: true,
      method: method,
      radius: radius,
      strength: strength,
      thickness: thickness,
    ),
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    // #region methods
    ChoiceControl(
      'Method',
      options: <String>[
        for (final AmbientOcclusionMethod m in AmbientOcclusionMethod.values)
          m.name,
      ],
      index: () => AmbientOcclusionMethod.values.indexOf(method),
      onChanged: (int i) => method = AmbientOcclusionMethod.values[i],
    ),
    // #endregion methods
    SliderControl(
      'Radius',
      min: 0.1,
      max: 2,
      value: () => radius,
      onChanged: (double v) => radius = v,
      format: (double v) => '${v.toStringAsFixed(2)} m',
    ),
    SliderControl(
      'Strength',
      min: 0,
      max: 1,
      value: () => strength,
      onChanged: (double v) => strength = v,
    ),
    SliderControl(
      'Thickness (ssil)',
      min: 0.05,
      max: 1,
      value: () => thickness,
      onChanged: (double v) => thickness = v,
      format: (double v) => '${v.toStringAsFixed(2)} m',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region ran
    if (strength > 0) expectPassOrDecline(frame, 'ssao');
    // #endregion ran
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
