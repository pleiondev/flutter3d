/// Light shafts: a view ray marched through the sun's own shadow map, so a
/// beam through a doorway has the doorway's shape.
///
/// Quoted by `light_shafts.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class LightShaftsDemo extends ShowcaseDemo {
  double strength = 0.25;
  double distance = 30.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 8.0
      ..pitch = 0.15
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 1.0, 2.0);
  }

  @override
  Scene build(DemoContext context) {
    final GraphicsDevice device = context.device;
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.35, 0.33, 0.3, 1.0),
      roughness: 0.9,
    );
    final Material floorStone = stone.copy()..doubleSided = true;

    // #region doorway
    final DeviceMesh pillar = DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3(1.2, 4.0, 1.2)).build(),
    );
    final MeshNode left = MeshNode(pillar, stone, name: 'left pillar')
      ..setPosition(-1.6, 2.0, -2.0);
    final MeshNode right = MeshNode(pillar, stone, name: 'right pillar')
      ..setPosition(1.6, 2.0, -2.0);
    final MeshNode lintel = MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(4.4, 0.8, 1.2)).build(),
      ),
      stone,
      name: 'lintel',
    )..setPosition(0.0, 4.4, -2.0);
    // #endregion doorway

    // #region sun
    final LightNode sun = LightNode(
      name: 'sun',
      intensity: 6.0,
      castsShadow: true,
    )..setLocalForward(Vector3(-0.3, -0.6, 0.7));
    // #endregion sun

    return Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            device,
            const PlaneShape(width: 20, depth: 20).build(),
          ),
          floorStone,
          name: 'floor',
        ),
      )
      ..add(left)
      ..add(right)
      ..add(lintel)
      ..add(sun);
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    lightShafts: LightShaftSettings(
      enabled: true,
      strength: strength,
      distance: distance,
    ),
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Strength',
      min: 0,
      max: 1,
      value: () => strength,
      onChanged: (double v) => strength = v,
    ),
    SliderControl(
      'Reach',
      min: 5,
      max: 60,
      value: () => distance,
      onChanged: (double v) => distance = v,
      format: (double v) => '${v.round()} m',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region ran
    if (!frame.passes.any((FramePass p) => p.name == 'light shafts')) {
      throw StateError('the light shafts pass did not run: ${frame.skipped}');
    }
    // #endregion ran
  }
}
