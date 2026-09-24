/// A penumbra that widens with distance: sharp where a shadow starts, soft
/// where it has travelled.
///
/// Quoted by `soft_shadows.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class SoftShadowsDemo extends ShowcaseDemo {
  double sunRadius = 0.05;
  double lampRadius = 0.3;
  int lightChoice = 0;

  late final LightNode _sun;
  late final LightNode _lamp;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 8.0
      ..pitch = 0.75
      ..yaw = 0.9;
  }

  @override
  Scene build(DemoContext context) {
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.78, 0.76, 0.72, 1.0),
      roughness: 0.9,
      doubleSided: true,
    );
    final Material clay = Material(
      name: 'clay',
      baseColor: Vector4(0.85, 0.45, 0.3, 1.0),
      roughness: 0.7,
    );

    // #region casters
    final Scene scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 12, depth: 12).build(),
          ),
          stone,
          name: 'ground',
        ),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const CylinderShape(
              radiusTop: 0.12,
              radiusBottom: 0.12,
              height: 3.0,
              segments: 16,
            ).build(),
          ),
          clay,
          name: 'pole',
        )..setPosition(-1.5, 1.5, 0.0),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(1.6, 0.15, 1.6)).build(),
          ),
          clay,
          name: 'slab',
        )..setPosition(1.5, 1.6, 0.0),
      );
    // #endregion casters

    // #region lights
    _sun = LightNode(name: 'sun', intensity: 3.0, castsShadow: true)
      ..setLocalForward(Vector3(-0.55, -0.7, -0.35));
    _lamp = LightNode(
      name: 'lamp',
      type: LightType.point,
      intensity: 60.0,
      range: 20.0,
    )..setPosition(2.5, 3.2, 2.5);
    scene
      ..add(_sun)
      ..add(_lamp);
    // #endregion lights
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    final bool lamp = lightChoice == 1;
    _sun
      ..castsShadow = !lamp
      ..intensity = lamp ? 0.0 : 3.0;
    _lamp
      ..castsShadow = lamp
      ..intensity = lamp ? 60.0 : 0.0;
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    shadows: ShadowSettings(
      cascades: 1,
      resolution: 1024,
      cubeResolution: 256,
      directionalLightRadius: sunRadius,
      pointLightRadius: lampRadius,
    ),
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Light',
      options: const <String>['Sun', 'Lamp'],
      index: () => lightChoice,
      onChanged: (int i) => lightChoice = i,
    ),
    SliderControl(
      'Sun size',
      min: 0,
      max: 0.2,
      value: () => sunRadius,
      onChanged: (double v) => sunRadius = v,
      format: (double v) => '${(v * 57.29578).toStringAsFixed(1)}°',
    ),
    SliderControl(
      'Lamp size',
      min: 0,
      max: 0.6,
      value: () => lampRadius,
      onChanged: (double v) => lampRadius = v,
      format: (double v) => '${v.toStringAsFixed(2)} m',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (!frame.passes.any((FramePass p) => p.name == 'directional shadows')) {
      throw StateError('the sun drew no shadow map to soften');
    }
    if (frame.shadowsDenied > 0) {
      throw StateError('the light was denied its shadow');
    }
  }
}
