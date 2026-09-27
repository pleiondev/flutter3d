/// Red paint twice: bare on the left, under a clear coat on the right.
///
/// Quoted by `clear_coat.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ClearCoatDemo extends ShowcaseDemo {
  double coat = 1.0;
  double coatRoughness = 0.15;
  double paintRoughness = 0.6;

  late final Material _bare;
  late final Material _coated;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.4
      ..yaw = 0.0
      ..pitch = 0.1;
  }

  @override
  Scene build(DemoContext context) {
    // #region paint
    _bare = Material(
      name: 'bare paint',
      lighting: LightingModel.pbrLayered,
      baseColor: Vector4(0.8, 0.05, 0.05, 1.0),
      roughness: paintRoughness,
    );
    _coated = Material(
      name: 'coated paint',
      lighting: LightingModel.pbrLayered,
      baseColor: Vector4(0.8, 0.05, 0.05, 1.0),
      roughness: paintRoughness,
      extensions: MaterialExtensions(
        clearcoat: coat,
        clearcoatRoughness: coatRoughness,
      ),
    );
    // #endregion paint

    // #region spheres
    final DeviceMesh ball = DeviceMesh.upload(
      context.device,
      SphereShape(radius: 0.5, segments: 48, rings: 24).build(),
    );
    final Scene scene = Scene()
      ..ambientIntensity = 0.15
      ..add(MeshNode(ball, _bare, name: 'bare')..setPosition(-0.6, 0.0, 0.0))
      ..add(MeshNode(ball, _coated, name: 'coated')..setPosition(0.6, 0.0, 0.0))
      ..add(
        LightNode(name: 'key', intensity: 3.0)
          ..setLocalForward(Vector3(-0.35, -0.45, -1.0).normalized()),
      );
    // #endregion spheres
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _bare.roughness = paintRoughness;
    _coated
      ..roughness = paintRoughness
      ..extensions = MaterialExtensions(
        clearcoat: coat,
        clearcoatRoughness: coatRoughness,
      );
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Coat',
      min: 0,
      max: 1,
      value: () => coat,
      onChanged: (double v) => coat = v,
    ),
    SliderControl(
      'Coat roughness',
      min: 0,
      max: 1,
      value: () => coatRoughness,
      onChanged: (double v) => coatRoughness = v,
    ),
    SliderControl(
      'Paint roughness',
      min: 0.05,
      max: 1,
      value: () => paintRoughness,
      onChanged: (double v) => paintRoughness = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final MeshNode coated = scene.meshes.firstWhere(
      (MeshNode m) => m.name == 'coated',
    );
    if (!identical(coated.material.lighting, LightingModel.pbrLayered)) {
      throw StateError('the coated paint is not on the layered model');
    }
    if (frame.drawCalls < 2) {
      throw StateError('the two spheres were not both drawn');
    }
  }
}
