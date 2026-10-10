/// Gold from polished to rough above, grey clay from half rough to fully rough
/// below: the two frame settings that keep rough surfaces from losing light.
///
/// Quoted by `rough_surfaces.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class RoughSurfacesDemo extends ShowcaseDemo {
  bool compensate = true;
  bool orenNayar = true;

  static const List<double> _metalRoughness = <double>[0.1, 0.3, 0.5, 0.7, 0.9];
  static const List<double> _clayRoughness = <double>[0.5, 0.75, 1.0];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 7.0
      ..yaw = 0.0
      ..pitch = 0.05;
  }

  @override
  Scene build(DemoContext context) {
    final DeviceMesh ball = DeviceMesh.upload(
      context.device,
      SphereShape(radius: 0.5, segments: 48, rings: 24).build(),
    );
    final Scene scene = Scene()
      ..ambientIntensity = 0.1 * Photometric.legacyUnit;

    // #region metals
    for (var i = 0; i < _metalRoughness.length; i++) {
      scene.add(
        MeshNode(
          ball,
          RenderMaterial(
            name: 'gold ${_metalRoughness[i]}',
            lighting: LightingModel.pbr,
            baseColor: LinearColor.fromSrgb(1.0, 0.78, 0.34, 1.0),
            metallic: 1.0,
            roughness: _metalRoughness[i],
          ),
          name: 'gold',
        )..setPosition((i - 2) * 1.15, 0.65, 0.0),
      );
    }
    // #endregion metals

    // #region clay
    for (var i = 0; i < _clayRoughness.length; i++) {
      scene.add(
        MeshNode(
          ball,
          RenderMaterial(
            name: 'clay ${_clayRoughness[i]}',
            lighting: LightingModel.pbr,
            baseColor: LinearColor.fromSrgb(0.42, 0.42, 0.42, 1.0),
            roughness: _clayRoughness[i],
          ),
          name: 'clay',
        )..setPosition((i - 1) * 1.15, -0.65, 0.0),
      );
    }
    // #endregion clay

    // #region light
    return scene..add(
      LightNode(name: 'key', intensity: 3.0 * Photometric.legacyUnit)
        ..setLocalForward(Vector3(-0.3, -0.4, -1.0).normalized()),
    );
    // #endregion light
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    energyCompensation: compensate,
    diffuseModel: orenNayar ? DiffuseModel.eon : DiffuseModel.lambert,
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Energy compensation',
      value: () => compensate,
      onChanged: (bool v) => compensate = v,
    ),
    ToggleControl(
      'Energy-preserving diffuse',
      value: () => orenNayar,
      onChanged: (bool v) => orenNayar = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final FramePass? pass = frame.passes
        .where((FramePass p) => p.name == 'scene')
        .firstOrNull;
    final int spheres = _metalRoughness.length + _clayRoughness.length;
    if (pass == null || pass.drawCalls < spheres) {
      throw StateError('the scene pass did not draw all $spheres spheres');
    }
  }
}
