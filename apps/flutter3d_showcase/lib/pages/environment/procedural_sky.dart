/// A sky that needs no image: a gradient, a glow and a sun disc, drawn by the
/// renderer from a few numbers.
///
/// Quoted by `procedural_sky.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ProceduralSkyDemo extends ShowcaseDemo {
  double sunHeight = 14.0;
  double sunDisc = 6.0;
  double glow = 0.4;
  bool dome = false;

  late final LightNode _sun;
  late final MeshNode _dome;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 7.0
      ..pitch = 0.1
      ..yaw = 0.9;
    context.orbit.target.setValues(0.0, 0.8, 0.0);
  }

  // The way to the sun for the current height, at a fixed compass bearing.
  Vector3 get _towardsSun {
    final double up = sunHeight * math.pi / 180.0;
    return Vector3(-math.cos(up) * 0.6, math.sin(up), -math.cos(up) * 0.8);
  }

  @override
  Scene build(DemoContext context) {
    final Material ground = Material(
      name: 'ground',
      baseColor: Vector4(0.42, 0.4, 0.36, 1.0),
      roughness: 0.9,
      doubleSided: true,
    );
    final Material ball = Material(
      name: 'ball',
      baseColor: Vector4(0.8, 0.8, 0.82, 1.0),
      roughness: 0.35,
    );
    // #region sun
    _sun = LightNode(name: 'sun', intensity: 3.0);
    // #endregion sun

    // #region dome
    final MeshData shell = const SkyDome().build();
    paintSky(
      shell,
      SkyGradient(
        zenith: Vector3(0.08, 0.2, 0.5),
        horizon: Vector3(0.5, 0.58, 0.68),
        nadir: Vector3(0.06, 0.06, 0.07),
      ).colour,
    );
    _dome = skyNode(DeviceMesh.upload(context.device, shell))..visible = false;
    // #endregion dome

    return Scene()
      ..ambientIntensity = 0.4
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 30, depth: 30).build(),
          ),
          ground,
          name: 'ground',
        ),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            SphereShape(radius: 0.8, segments: 32, rings: 16).build(),
          ),
          ball,
          name: 'ball',
        )..setPosition(0.0, 0.8, 0.0),
      )
      ..add(_sun)
      ..add(_dome);
  }

  @override
  void update(DemoContext context, double dt) {
    _sun.setLocalForward(-_towardsSun);
    _dome.visible = dome;
    // The dome is small and has to follow the eye, or it is a ball on the
    // ground.
    followCamera(_dome, context.camera);
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region sky
    sky: SkySettings(
      enabled: !dome,
      directionToSun: _towardsSun,
      sunIntensity: sunDisc,
      glowStrength: glow,
    ),
    // #endregion sky
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Sun height',
      min: 2,
      max: 85,
      value: () => sunHeight,
      onChanged: (double v) => sunHeight = v,
      format: (double v) => '${v.round()} deg',
    ),
    SliderControl(
      'Sun disc',
      min: 0,
      max: 20,
      value: () => sunDisc,
      onChanged: (double v) => sunDisc = v,
    ),
    SliderControl(
      'Glow',
      min: 0,
      max: 1,
      value: () => glow,
      onChanged: (double v) => glow = v,
    ),
    ToggleControl(
      'Painted dome instead',
      value: () => dome,
      onChanged: (bool v) => dome = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final FramePass draw = frame.passes.firstWhere(
      (FramePass p) => p.name == 'scene',
    );
    final int meshes = scene.meshes.where((MeshNode m) => m.visible).length;
    // The sky is one full-screen triangle inside the scene pass, so it is the
    // draw that comes on top of the meshes.
    if (draw.drawCalls != meshes + 1) {
      throw StateError(
        'expected $meshes mesh draws and one for the sky, '
        'got ${draw.drawCalls}',
      );
    }
  }
}
