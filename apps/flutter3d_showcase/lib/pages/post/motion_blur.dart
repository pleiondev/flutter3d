/// Motion blur: what moved while the shutter was open, smeared along the way
/// it moved.
///
/// Quoted by `motion_blur.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class MotionBlurDemo extends ShowcaseDemo {
  bool blur = true;
  double shutter = 0.5;
  double maxRadius = 20.0;
  double speed = 8.0;

  /// The wheel's angle, in radians, which [update] advances.
  double _angle = 0.0;

  late final SceneNode _wheel;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.0
      ..pitch = 0.0
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 0.0, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    final GraphicsDevice device = context.device;
    // #region wheel
    final DeviceMesh spoke = DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3(3.0, 0.3, 0.3)).build(),
    );
    final List<Vector4> colours = <Vector4>[
      Vector4(0.9, 0.8, 0.2, 1.0),
      Vector4(0.2, 0.7, 0.9, 1.0),
      Vector4(0.9, 0.3, 0.3, 1.0),
    ];
    _wheel = SceneNode(name: 'wheel');
    for (int i = 0; i < 3; i++) {
      _wheel.add(
        MeshNode(spoke, Material(baseColor: colours[i]), name: 'spoke $i')
          ..setRotationYawPitchRoll(0.0, 0.0, i * math.pi / 3),
      );
    }
    _wheel.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          const CylinderShape(
            radiusTop: 0.35,
            radiusBottom: 0.35,
            height: 0.5,
          ).build(),
        ),
        Material(baseColor: Vector4(0.5, 0.5, 0.5, 1.0)),
        name: 'hub',
      )..setRotationYawPitchRoll(0.0, math.pi / 2, 0.0),
    );
    // #endregion wheel

    final MeshNode backdrop = MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(14.0, 9.0, 0.1)).build(),
      ),
      Material(baseColor: Vector4(0.35, 0.35, 0.38, 1.0), roughness: 0.9),
      name: 'backdrop',
    )..setPosition(0.0, 0.0, -1.0);
    final LightNode sun = LightNode(name: 'sun', intensity: 3.0)
      ..castsShadow = false
      ..setLocalForward(Vector3(-2.0, -3.0, -4.0).normalized());
    return Scene()
      ..add(backdrop)
      ..add(_wheel)
      ..add(sun);
  }

  @override
  void update(DemoContext context, double dt) {
    // #region turn
    _angle += speed * dt;
    _wheel.setRotationYawPitchRoll(0.0, 0.0, _angle);
    // #endregion turn
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    motionBlur: MotionBlurSettings(
      enabled: blur,
      shutterFraction: shutter,
      maxRadius: maxRadius,
    ),
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Motion blur',
      value: () => blur,
      onChanged: (bool v) => blur = v,
    ),
    SliderControl(
      'Shutter',
      min: 0,
      max: 1,
      value: () => shutter,
      onChanged: (double v) => shutter = v,
      format: (double v) => '${(v * 360).round()}°',
    ),
    SliderControl(
      'Streak each side',
      min: 1,
      max: 64,
      value: () => maxRadius,
      onChanged: (double v) => maxRadius = v,
      format: (double v) => '${v.round()} px',
    ),
    SliderControl(
      'Speed',
      min: 0,
      max: 20,
      value: () => speed,
      onChanged: (double v) => speed = v,
      format: (double v) => '${v.toStringAsFixed(1)} rad/s',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region ran
    if (blur) {
      expectPassOrDecline(frame, 'motion blur');
    } else if (passRan(frame, 'motion blur')) {
      throw StateError('motion blur is off and its pass ran');
    }
    // #endregion ran
  }
}
