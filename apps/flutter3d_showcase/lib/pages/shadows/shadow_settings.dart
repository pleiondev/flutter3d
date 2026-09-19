/// The knobs that decide how good the sun's shadow looks: the size of its map,
/// the bias that keeps it clean, how dark it is and how far it is fitted for.
///
/// Quoted by `shadow_settings.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ShadowSettingsDemo extends ShowcaseDemo {
  int resolutionChoice = 0;
  double bias = 0.0015;
  double strength = 1.0;
  double viewDistance = 40.0;

  static const List<int> _resolutions = <int>[256, 512, 1024, 2048];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.0
      ..pitch = 0.6
      ..yaw = 0.6;
  }

  @override
  Scene build(DemoContext context) {
    // #region ground
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.75, 0.73, 0.68, 1.0),
      roughness: 0.9,
    );
    final Scene scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 14, depth: 14).build(),
          ),
          stone,
          name: 'ground',
        ),
      );
    // #endregion ground

    // #region casters
    final Material clay = Material(
      name: 'clay',
      baseColor: Vector4(0.85, 0.45, 0.3, 1.0),
      roughness: 0.7,
    );
    scene
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(1.2, 2.4, 1.2)).build(),
          ),
          clay,
          name: 'column',
        )..setPosition(-1.5, 1.2, 0.0),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            SphereShape(radius: 0.8, segments: 32, rings: 16).build(),
          ),
          clay,
          name: 'ball',
        )..setPosition(1.5, 0.8, 0.5),
      );
    // #endregion casters

    // #region sun
    scene.add(
      LightNode(name: 'sun', intensity: 3.0, castsShadow: true)
        ..setLocalForward(Vector3(-0.5, -0.9, -0.4)),
    );
    // #endregion sun
    return scene;
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    shadows: ShadowSettings(
      cascades: 2,
      resolution: _resolutions[resolutionChoice],
      bias: bias,
      strength: strength,
      viewDistance: viewDistance,
    ),
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Map size',
      options: <String>[for (final int r in _resolutions) '$r'],
      index: () => resolutionChoice,
      onChanged: (int i) => resolutionChoice = i,
    ),
    SliderControl(
      'Bias',
      min: 0,
      max: 0.02,
      value: () => bias,
      onChanged: (double v) => bias = v,
      format: (double v) => v.toStringAsFixed(4),
    ),
    SliderControl(
      'Strength',
      min: 0,
      max: 1,
      value: () => strength,
      onChanged: (double v) => strength = v,
    ),
    SliderControl(
      'Distance',
      min: 3,
      max: 40,
      value: () => viewDistance,
      onChanged: (double v) => viewDistance = v,
      format: (double v) => '${v.round()} m',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (!frame.passes.any((FramePass p) => p.name == 'directional shadows')) {
      throw StateError('the sun drew no shadow map');
    }
    if (frame.shadowCasters < 2) {
      throw StateError(
        'expected the column and the ball in the map, '
        'got ${frame.shadowCasters}',
      );
    }
  }
}
