/// Screen-space reflections: a ray marched through the picture the scene
/// already drew, so a polished floor shows what stands on it.
///
/// Quoted by `screen_space_reflections.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ScreenSpaceReflectionsDemo extends ShowcaseDemo {
  double roughness = 0.05;
  double intensity = 1.0;

  late final Material _floor;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.0
      ..pitch = 0.28
      ..yaw = 0.5;
    context.orbit.target.setValues(0.0, 0.3, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    // #region floor
    _floor = Material(
      name: 'floor',
      baseColor: Vector4(0.06, 0.06, 0.07, 1.0),
      roughness: roughness,
    );
    final MeshNode floorMesh = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(10.0, 0.3, 10.0)).build(),
      ),
      _floor,
      name: 'floor',
    );
    // #endregion floor

    // #region beacon
    final MeshNode beacon = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3.all(1.0)).build(),
      ),
      Material(
        name: 'beacon',
        baseColor: Vector4(0.0, 0.0, 0.0, 1.0),
        emissive: Vector3(1.0, 0.4, 0.1),
        emissiveStrength: 2.0,
      ),
      name: 'beacon',
    )..setPosition(0.0, 0.65, 0.0);
    // #endregion beacon

    return Scene()
      ..add(floorMesh)
      ..add(beacon)
      ..add(
        LightNode(name: 'sun', intensity: 1.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    _floor.roughness = roughness;
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    reflections: ReflectionSettings(enabled: true, intensity: intensity),
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Roughness',
      min: 0.02,
      max: 0.4,
      value: () => roughness,
      onChanged: (double v) => roughness = v,
    ),
    SliderControl(
      'Intensity',
      min: 0,
      max: 1.5,
      value: () => intensity,
      onChanged: (double v) => intensity = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region ran
    if (!frame.passes.any((FramePass p) => p.name == 'reflections')) {
      throw StateError('the reflections pass did not run: ${frame.skipped}');
    }
    // #endregion ran
  }
}
