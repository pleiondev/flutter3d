/// Depth of field from a thin lens: a focus distance, a focal length and an
/// f-number, the same three numbers a photographer already knows.
///
/// Quoted by `depth_of_field.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class DepthOfFieldDemo extends ShowcaseDemo {
  double focusDistance = 4.0;
  double aperture = 2.0;
  double focalLength = 0.085;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.0
      ..pitch = 0.0
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 0.0, -4.0);
  }

  @override
  Scene build(DemoContext context) {
    // #region row
    final Scene scene = Scene();
    final DeviceMesh post = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(0.4, 1.6, 0.4)).build(),
    );
    for (var i = 0; i < 6; i++) {
      final double z = -1.0 - i * 2.0;
      scene.add(
        MeshNode(
          post,
          Material(
            name: 'post $i',
            baseColor: Vector4(0.85, 0.4 + i * 0.08, 0.2, 1.0),
          ),
          name: 'post $i',
        )..setPosition(0.0, 0.0, z),
      );
    }
    // #endregion row
    return scene..add(
      LightNode(name: 'sun', intensity: 3.0)
        ..setLocalForward(Vector3(-0.3, -0.7, -0.4)),
    );
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region lens
    depthOfField: DepthOfFieldSettings(
      enabled: true,
      focusDistance: focusDistance,
      focalLength: focalLength,
      aperture: aperture,
    ),
    // #endregion lens
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Focus distance',
      min: 1,
      max: 11,
      value: () => focusDistance,
      onChanged: (double v) => focusDistance = v,
      format: (double v) => '${v.toStringAsFixed(1)} m',
    ),
    SliderControl(
      'Aperture (f/)',
      min: 1.4,
      max: 16,
      value: () => aperture,
      onChanged: (double v) => aperture = v,
      format: (double v) => v.toStringAsFixed(1),
    ),
    SliderControl(
      'Focal length',
      min: 0.024,
      max: 0.135,
      value: () => focalLength,
      onChanged: (double v) => focalLength = v,
      format: (double v) => '${(v * 1000).round()} mm',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region ran
    if (!frame.passes.any((FramePass p) => p.name == 'depth of field')) {
      throw StateError('the depth of field pass did not run: ${frame.skipped}');
    }
    // #endregion ran
  }
}
