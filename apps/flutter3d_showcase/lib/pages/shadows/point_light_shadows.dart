/// Shadows from a lamp and from a spotlight, drawn into a cube map.
///
/// Quoted by `point_light_shadows.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class PointLightShadowsDemo extends ShowcaseDemo {
  double softness = 4.0;
  double bias = 0.08;
  int sizeChoice = 1;
  int facesChoice = 1;

  static const List<int> _sizes = <int>[128, 256, 512];
  static const List<ShadowCasterFaces> _faces = <ShadowCasterFaces>[
    ShadowCasterFaces.front,
    ShadowCasterFaces.back,
    ShadowCasterFaces.both,
  ];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.0
      ..pitch = 0.55
      ..yaw = 0.7;
  }

  @override
  Scene build(DemoContext context) {
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.78, 0.76, 0.72, 1.0),
      roughness: 0.9,
    );
    final Material floorStone = stone.copy()..doubleSided = true;
    final Material clay = Material(
      name: 'clay',
      baseColor: Vector4(0.85, 0.45, 0.3, 1.0),
      roughness: 0.7,
    );
    final Scene scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 12, depth: 12).build(),
          ),
          floorStone,
          name: 'floor',
        ),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(12.0, 4.0, 0.3)).build(),
          ),
          stone,
          name: 'wall',
        )..setPosition(0.0, 2.0, -5.0),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(1.0, 2.0, 1.0)).build(),
          ),
          clay,
          name: 'column',
        )..setPosition(-1.0, 1.0, -1.0),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            SphereShape(radius: 0.7, segments: 24, rings: 12).build(),
          ),
          clay,
          name: 'ball',
        )..setPosition(1.8, 0.7, -2.0),
      );

    // #region lamp
    scene.add(
      LightNode(
        name: 'lamp',
        type: LightType.point,
        intensity: 50.0,
        range: 16.0,
        castsShadow: true,
      )..setPosition(1.5, 3.2, 1.0),
    );
    // #endregion lamp

    // #region spot
    scene.add(
      LightNode(
          name: 'spot',
          type: LightType.spot,
          intensity: 90.0,
          range: 16.0,
          innerConeAngle: 0.2,
          outerConeAngle: 0.5,
          castsShadow: true,
        )
        ..setPosition(-4.0, 3.5, 3.5)
        ..lookAt(Vector3(-1.0, 0.5, -1.5)),
    );
    // #endregion spot
    return scene;
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    shadows: ShadowSettings(
      cubeResolution: _sizes[sizeChoice],
      pointBias: bias,
      pointSoftness: softness,
      casterFaces: _faces[facesChoice],
    ),
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Softness',
      min: 0,
      max: 16,
      value: () => softness,
      onChanged: (double v) => softness = v,
      format: (double v) => '${v.toStringAsFixed(1)} texels',
    ),
    SliderControl(
      'Bias',
      min: 0,
      max: 0.5,
      value: () => bias,
      onChanged: (double v) => bias = v,
      format: (double v) => '${v.toStringAsFixed(2)} m',
    ),
    ChoiceControl(
      'Face size',
      options: <String>[for (final int s in _sizes) '$s'],
      index: () => sizeChoice,
      onChanged: (int i) => sizeChoice = i,
    ),
    ChoiceControl(
      'Casters draw',
      options: const <String>['Front', 'Back', 'Both'],
      index: () => facesChoice,
      onChanged: (int i) => facesChoice = i,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (!frame.passes.any((FramePass p) => p.name == 'point shadows')) {
      throw StateError('no cube shadow pass ran');
    }
    if (frame.shadowsDenied > 0) {
      throw StateError(
        '${frame.shadowsDenied} light(s) asked for a shadow and were refused',
      );
    }
  }
}
