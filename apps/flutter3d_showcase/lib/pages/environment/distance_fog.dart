/// Distance fog: things farther from the eye fade toward one colour.
///
/// Quoted by `distance_fog.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class DistanceFogDemo extends ShowcaseDemo {
  double density = 0.03;
  bool matchSky = true;

  // #region sky
  static const SkySettings _sky = SkySettings(enabled: true);
  // #endregion sky

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.0
      ..pitch = 0.08
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 1.2, -10.0);
    context.orbit.apply();
  }

  @override
  Scene build(DemoContext context) {
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.62, 0.58, 0.52, 1.0),
      roughness: 0.9,
    );
    final DeviceMesh pillar = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(1.2, 3.0, 1.2)).build(),
    );
    final Scene scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 120, depth: 120).build(),
          ),
          stone.copy()..doubleSided = true,
          name: 'floor',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -0.8, -0.5)),
      );
    // #region pillars
    for (var i = 0; i < 12; i++) {
      scene.add(
        MeshNode(pillar, stone, name: 'pillar $i')
          ..setPosition(i.isEven ? -3.0 : 3.0, 1.5, -i * 4.5),
      );
    }
    // #endregion pillars
    return scene;
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    sky: _sky,
    // #region fog
    fog: FogSettings(
      // Read off the sky at the horizon, so the far end melts into it.
      color: matchSky
          ? _sky.sample(Vector3(0.0, 0.0, -1.0))
          : Vector3(0.6, 0.2, 0.2),
      density: density,
    ),
    // #endregion fog
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Density',
      min: 0,
      max: 0.2,
      value: () => density,
      onChanged: (double v) => density = v,
      format: (double v) => v.toStringAsFixed(3),
    ),
    ToggleControl(
      'Fog takes the sky colour',
      value: () => matchSky,
      onChanged: (bool v) => matchSky = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < scene.meshes.length) {
      throw StateError('some of the pillars were not drawn');
    }
  }
}
