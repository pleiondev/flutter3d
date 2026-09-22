/// `RenderSettings.specular`: one scalar that turns the whole frame's
/// specular response up or down without touching a single material.
///
/// Quoted by `specular_scale.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class SpecularScaleDemo extends ShowcaseDemo {
  double specular = 1.5;

  late final Material _ball;
  late final LightNode _sun;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.5
      ..pitch = 0.15;
  }

  @override
  Scene build(DemoContext context) {
    // #region material
    _ball = Material(
      name: 'ball',
      lighting: LightingModel.pbr,
      baseColor: Vector4(0.75, 0.2, 0.2, 1.0),
      metallic: 0.9,
      roughness: 0.18,
    );
    // #endregion material

    final MeshNode ball = MeshNode(
      DeviceMesh.upload(
        context.device,
        SphereShape(segments: 48, rings: 24).build(),
      ),
      _ball,
      name: 'ball',
    );

    // #region light
    _sun = LightNode(name: 'sun', intensity: 3.0)
      ..setLocalForward(Vector3(-0.3, -0.6, -0.7));
    // #endregion light

    return Scene()
      ..add(ball)
      ..add(_sun);
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    specular: specular,
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Specular',
      min: 0,
      max: 3,
      value: () => specular,
      onChanged: (double v) => specular = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_ball.metallic < 0.5 || _ball.roughness > 0.4) {
      throw StateError('the ball is not shiny enough to show a highlight');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // #endregion check
  }
}
