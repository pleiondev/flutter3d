/// The sun's shadow, split into cascades so that it is sharp near you and
/// still reaches the horizon.
///
/// Quoted by `cascaded_shadows.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class CascadedShadowsDemo extends ShowcaseDemo {
  int cascades = 3;
  double split = 0.7;
  double viewDistance = 60.0;
  int resolutionChoice = 1;

  static const List<int> _resolutions = <int>[512, 1024, 2048];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.0
      ..pitch = 0.35
      ..yaw = 0.5;
    context.orbit.target.setValues(0.0, 1.0, -14.0);
  }

  @override
  Scene build(DemoContext context) {
    // #region floor
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.72, 0.7, 0.66, 1.0),
      roughness: 0.85,
    );
    final MeshNode floor = MeshNode(
      DeviceMesh.upload(
        context.device,
        const PlaneShape(width: 80, depth: 80).build(),
      ),
      stone,
      name: 'floor',
    );
    // #endregion floor

    // #region pillars
    final Scene scene = Scene()..add(floor);
    final DeviceMesh pillar = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(1.0, 3.0, 1.0)).build(),
    );
    for (var i = 0; i < 10; i++) {
      scene.add(
        MeshNode(pillar, stone, name: 'pillar $i')
          ..setPosition(i.isEven ? -3.0 : 3.0, 1.5, -i * 5.0),
      );
    }
    // #endregion pillars

    // #region sun
    scene.add(
      LightNode(name: 'sun', intensity: 3.0, castsShadow: true)
        ..setLocalForward(Vector3(-0.5, -0.8, -0.3)),
    );
    // #endregion sun
    return scene;
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    shadows: ShadowSettings(
      cascades: cascades,
      cascadeSplit: split,
      viewDistance: viewDistance,
      resolution: _resolutions[resolutionChoice],
    ),
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Cascades',
      min: 1,
      max: 4,
      divisions: 3,
      value: () => cascades.toDouble(),
      onChanged: (double v) => cascades = v.round(),
      format: (double v) => '${v.round()}',
    ),
    SliderControl(
      'Split',
      min: 0.1,
      max: 0.95,
      value: () => split,
      onChanged: (double v) => split = v,
    ),
    SliderControl(
      'Shadow distance',
      min: 10,
      max: 120,
      value: () => viewDistance,
      onChanged: (double v) => viewDistance = v,
      format: (double v) => '${v.round()} m',
    ),
    ChoiceControl(
      'Map size',
      options: <String>[for (final int r in _resolutions) '$r'],
      index: () => resolutionChoice,
      onChanged: (int i) => resolutionChoice = i,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.shadowsDenied > 0) {
      throw StateError('the sun was denied its shadow');
    }
  }
}
