/// A physically based material: how metallic it is, how rough, and a light.
///
/// This page is quoted by its guide, `pbr_lighting.md`, region by region, and
/// shown whole in the Source tab. Everything outside the regions is the small
/// amount the host needs to run it.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class PbrLightingDemo extends ShowcaseDemo {
  double metallic = 0.0;
  double roughness = 0.4;
  double sunIntensity = 3.0;

  late final Material _ball;
  late final LightNode _sun;

  @override
  Scene build(DemoContext context) {
    // #region material
    _ball = Material(
      name: 'ball',
      lighting: LightingModel.pbr,
      baseColor: Vector4(0.9, 0.42, 0.28, 1.0),
      metallic: metallic,
      roughness: roughness,
    );
    // #endregion material

    // #region mesh
    final MeshNode ball = MeshNode(
      DeviceMesh.upload(
        context.device,
        SphereShape(segments: 48, rings: 24).build(),
      ),
      _ball,
      name: 'ball',
    );
    // #endregion mesh

    // #region light
    _sun = LightNode(name: 'sun', intensity: sunIntensity)
      ..setLocalForward(Vector3(-0.4, -1.0, -0.3));
    // #endregion light

    return Scene()
      ..add(ball)
      ..add(_sun);
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _ball
      ..metallic = metallic
      ..roughness = roughness;
    _sun.intensity = sunIntensity;
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Metallic',
      min: 0,
      max: 1,
      value: () => metallic,
      onChanged: (double v) => metallic = v,
    ),
    SliderControl(
      'Roughness',
      min: 0.05,
      max: 1,
      value: () => roughness,
      onChanged: (double v) => roughness = v,
    ),
    SliderControl(
      'Sun',
      min: 0,
      max: 6,
      value: () => sunIntensity,
      onChanged: (double v) => sunIntensity = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
  }
}
