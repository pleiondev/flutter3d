/// FXAA: edges smoothed on the finished picture, and a sharpen pass that
/// shares its taps.
///
/// Quoted by `anti_aliasing.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class AntiAliasingDemo extends ShowcaseDemo {
  bool enabled = true;
  double sharpen = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.5
      ..pitch = 0.0
      ..yaw = 0.0;
    context.orbit.apply();
  }

  @override
  Scene build(DemoContext context) {
    // #region card
    final MeshNode card = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(2.4, 2.4, 0.2)).build(),
      ),
      Material(
        name: 'card',
        baseColor: Vector4(0.95, 0.95, 0.95, 1.0),
        lighting: LightingModel.unlit,
      ),
    )..setLocalMatrix(Matrix4.rotationZ(0.37));
    // #endregion card
    return Scene()..add(card);
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    antiAlias: AntiAliasSettings(enabled: enabled, sharpen: sharpen),
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'FXAA',
      value: () => enabled,
      onChanged: (bool v) => enabled = v,
    ),
    SliderControl(
      'Sharpen',
      min: 0,
      max: 1,
      value: () => sharpen,
      onChanged: (double v) => sharpen = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region reported
    final bool ran = frame.antiAliasing.fxaa;
    if (ran != enabled) {
      throw StateError(
        'the frame reports fxaa: $ran while the page asked '
        'for $enabled',
      );
    }
    // #endregion reported
  }
}
