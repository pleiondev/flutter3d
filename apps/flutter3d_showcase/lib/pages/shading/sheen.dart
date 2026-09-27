/// Red cloth twice: bare on the left, with a sheen at its rim on the right.
///
/// Quoted by `sheen.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class SheenDemo extends ShowcaseDemo {
  int colour = 0;
  double sheenRoughness = 0.5;

  static const List<String> _colourNames = <String>['Blue', 'White', 'Gold'];

  late final Material _cloth;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.4
      ..yaw = 0.0
      ..pitch = 0.1;
  }

  // #region colours
  /// Linear colours: the sheen is not painted, so it is not sRGB.
  Vector3 _sheenColour() => switch (colour) {
    0 => Vector3(0.2, 0.4, 1.0),
    1 => Vector3(1.0, 1.0, 1.0),
    _ => Vector3(1.0, 0.75, 0.3),
  };
  // #endregion colours

  @override
  Scene build(DemoContext context) {
    // #region cloth
    final Material bare = Material(
      name: 'bare cloth',
      lighting: LightingModel.pbrLayered,
      baseColor: Vector4(0.8, 0.05, 0.05, 1.0),
      roughness: 0.6,
    );
    _cloth = Material(
      name: 'cloth with sheen',
      lighting: LightingModel.pbrLayered,
      baseColor: Vector4(0.8, 0.05, 0.05, 1.0),
      roughness: 0.6,
      extensions: MaterialExtensions(
        sheenColor: _sheenColour(),
        sheenRoughness: sheenRoughness,
      ),
    );
    // #endregion cloth

    final DeviceMesh ball = DeviceMesh.upload(
      context.device,
      SphereShape(radius: 0.5, segments: 48, rings: 24).build(),
    );
    return Scene()
      ..ambientIntensity = 0.15
      ..add(MeshNode(ball, bare, name: 'bare')..setPosition(-0.6, 0.0, 0.0))
      ..add(MeshNode(ball, _cloth, name: 'sheen')..setPosition(0.6, 0.0, 0.0))
      ..add(
        LightNode(name: 'key', intensity: 3.0)
          ..setLocalForward(Vector3(-0.35, -0.45, -1.0).normalized()),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _cloth.extensions = MaterialExtensions(
      sheenColor: _sheenColour(),
      sheenRoughness: sheenRoughness,
    );
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Sheen colour',
      options: _colourNames,
      index: () => colour,
      onChanged: (int i) => colour = i,
    ),
    SliderControl(
      'Sheen roughness',
      min: 0,
      max: 1,
      value: () => sheenRoughness,
      onChanged: (double v) => sheenRoughness = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final MeshNode cloth = scene.meshes.firstWhere(
      (MeshNode m) => m.name == 'sheen',
    );
    if (cloth.material.extensions?.shades != true) {
      throw StateError('the cloth has no layer that changes its shading');
    }
    if (frame.drawCalls < 2) {
      throw StateError('the two spheres were not both drawn');
    }
  }
}
