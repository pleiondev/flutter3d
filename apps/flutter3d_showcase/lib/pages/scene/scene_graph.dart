/// A small hierarchy whose child transforms follow two rotating pivots.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class SceneGraphDemo extends ShowcaseDemo {
  double speed = 0.7;

  late final SceneNode _systemPivot;
  late final SceneNode _planetPivot;
  late final SceneNode _moonPivot;
  late final MeshNode _moon;
  late final Vector3 _initialMoonPosition;
  late final int _initialMoonVersion;

  double _angle = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 10.0
      ..pitch = 0.4
      ..yaw = 0.35;
  }

  @override
  Scene build(DemoContext context) {
    final DeviceMesh sphere = DeviceMesh.upload(
      context.device,
      const SphereShape(segments: 32, rings: 16).build(),
    );

    // #region hierarchy
    _systemPivot = SceneNode(name: 'system pivot');
    _planetPivot = SceneNode(name: 'planet orbit')..setPosition(3.1, 0.0, 0.0);
    _moonPivot = SceneNode(name: 'moon orbit')..setPosition(1.15, 0.0, 0.0);

    final MeshNode planet = MeshNode(
      sphere,
      Material(
        name: 'blue planet',
        baseColor: Vector4(0.18, 0.48, 0.88, 1.0),
        roughness: 0.62,
      ),
      name: 'planet',
    )..setUniformScale(0.72);
    _moon = MeshNode(
      sphere,
      Material(
        name: 'moon rock',
        baseColor: Vector4(0.72, 0.7, 0.66, 1.0),
        roughness: 0.92,
      ),
      name: 'moon',
    )..setUniformScale(0.25);

    _systemPivot.add(_planetPivot);
    _planetPivot
      ..add(planet)
      ..add(_moonPivot);
    _moonPivot.add(_moon);
    // #endregion hierarchy

    // #region root
    final MeshNode star = MeshNode(
      sphere,
      Material(
        name: 'star',
        baseColor: Vector4(1.0, 0.56, 0.12, 1.0),
        emissive: Vector3(1.0, 0.28, 0.04),
        emissiveStrength: 1.8,
        roughness: 0.5,
      ),
      name: 'star',
    )..setUniformScale(1.15);
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.2, 0.26, 0.42)
      ..ambientIntensity = 0.12
      ..add(star)
      ..add(_systemPivot)
      ..add(
        LightNode(
          type: LightType.point,
          intensity: 24.0,
          range: 12.0,
          name: 'starlight',
        ),
      );
    // #endregion root

    _initialMoonPosition = _moon.readWorldPosition();
    _initialMoonVersion = _moon.worldVersion;
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    // #region motion
    _angle += dt * speed;
    _systemPivot.setRotationYawPitchRoll(_angle, 0.0, 0.0);
    _planetPivot.setRotationYawPitchRoll(_angle * 2.7, 0.0, 0.0);
    // #endregion motion
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Orbit speed',
      min: 0.0,
      max: 2.0,
      value: () => speed,
      onChanged: (double value) => speed = value,
      format: (double value) => value.toStringAsFixed(2),
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final Vector3 current = _moon.readWorldPosition();
    final bool hierarchyIsIntact =
        _moon.parent == _moonPivot &&
        _moonPivot.parent == _planetPivot &&
        _planetPivot.parent == _systemPivot;
    if (!hierarchyIsIntact ||
        (current - _initialMoonPosition).length < 0.001 ||
        _moon.worldVersion == _initialMoonVersion ||
        frame.drawCalls < 3) {
      throw StateError('the child transforms did not follow their parents');
    }
    // #endregion check
  }
}
