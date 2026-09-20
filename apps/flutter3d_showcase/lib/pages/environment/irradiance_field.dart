/// One bounce of diffuse light: a grid of probes, each filled by casting rays
/// out from it and recording what colour comes back.
///
/// Quoted by `irradiance_field.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class IrradianceFieldDemo extends ShowcaseDemo {
  bool baked = true;
  double ambient = 0.5;

  late final IrradianceField _field;
  late final Scene _scene;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.0
      ..pitch = 0.35
      ..yaw = 0.5;
    context.orbit.target.setValues(-0.5, 1.0, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    final Material floor = Material(
      name: 'floor',
      baseColor: Vector4(0.55, 0.55, 0.55, 1.0),
      roughness: 0.95,
      doubleSided: true,
    );
    final Material wall = Material(
      name: 'red wall',
      baseColor: Vector4(0.85, 0.08, 0.08, 1.0),
      roughness: 0.95,
      doubleSided: true,
    );

    final MeshNode wallNode =
        MeshNode(
            DeviceMesh.upload(
              context.device,
              const PlaneShape(width: 3, depth: 4).build(),
            ),
            wall,
            name: 'wall',
          )
          ..setPosition(-2.0, 1.5, 0.0)
          ..setRotation(Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), -1.5708));

    final Scene scene = _scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 6, depth: 6).build(),
          ),
          floor,
          name: 'floor',
        ),
      )
      ..add(wallNode)
      ..add(
        LightNode(name: 'sun', intensity: 4.0)
          ..setLocalForward(Vector3(-0.6, -0.7, 0.15)),
      );

    // #region field
    _field = IrradianceField(
      origin: Vector3(-1.0, 0.5, -1.0),
      spacing: Vector3(1.0, 1.0, 1.0),
      countX: 2,
      countY: 2,
      countZ: 2,
    );
    // #endregion field

    // #region gather
    gather(_field, scene, rays: 96);
    // #endregion gather

    return scene;
  }

  // #region live
  @override
  void update(DemoContext context, double dt) {
    _scene.irradianceField = baked ? _field : null;
    _scene.ambientIntensity = ambient;
  }
  // #endregion live

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Field on',
      value: () => baked,
      onChanged: (bool v) => baked = v,
    ),
    SliderControl(
      'Ambient strength',
      min: 0,
      max: 2,
      value: () => ambient,
      onChanged: (double v) => ambient = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final Vector3 towardWall = _field.sample(
      Vector3(-0.5, 1.0, -0.5),
      Vector3(-1.0, 0.0, 0.0),
    );
    final Vector3 awayFromWall = _field.sample(
      Vector3(-0.5, 1.0, -0.5),
      Vector3(1.0, 0.0, 0.0),
    );
    if (towardWall.x < 0.01 || towardWall.x <= awayFromWall.x * 1.5) {
      throw StateError(
        'the probe facing the red wall ($towardWall) is not redder than the '
        'one facing away from it ($awayFromWall); the bounce never arrived',
      );
    }
  }
}
