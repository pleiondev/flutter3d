/// A small mixed scene whose result exposes useful frame counters.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class FrameStatsDemo extends ShowcaseDemo {
  bool shadows = true;

  late final LightNode _sun;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 8.0
      ..pitch = 0.3
      ..yaw = 0.5;
    context.orbit.target.setValues(0.0, 0.7, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    // #region geometry
    final Material matte = Material(
      name: 'matte',
      baseColor: Vector4(0.24, 0.62, 0.82, 1.0),
      roughness: 0.72,
    );
    final Material metal = Material(
      name: 'metal',
      baseColor: Vector4(0.82, 0.43, 0.18, 1.0),
      metallic: 0.76,
      roughness: 0.24,
    );
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.42, 0.5, 0.68)
      ..ambientIntensity = 0.12
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 8.0, depth: 7.0).build(),
          ),
          matte.copy()..doubleSided = true,
          name: 'floor',
        )..castsShadow = false,
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3.all(1.5)).build(),
          ),
          matte,
          name: 'cube',
        )..setPosition(-1.25, 0.75, 0.0),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const TorusShape(radius: 0.72, tubeRadius: 0.28).build(),
          ),
          metal,
          name: 'torus',
        )..setPosition(1.35, 1.0, 0.0),
      );
    // #endregion geometry

    // #region light
    _sun = LightNode(name: 'sun', intensity: 3.2, castsShadow: shadows)
      ..setLocalForward(Vector3(-0.45, -0.82, -0.35));
    scene.add(_sun);
    // #endregion light
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    _sun.castsShadow = shadows;
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Shadow pass',
      value: () => shadows,
      onChanged: (bool value) => shadows = value,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region totals
    final FramePass scenePass = frame.passes.firstWhere(
      (FramePass pass) => pass.name == 'scene',
    );
    final FramePass compositePass = frame.passes.firstWhere(
      (FramePass pass) => pass.name == 'composite',
    );
    final int passDraws = frame.passes.fold<int>(
      0,
      (int total, FramePass pass) => total + pass.drawCalls,
    );
    // #endregion totals

    // #region check
    if (scenePass.drawCalls < 3 ||
        compositePass.drawCalls != 1 ||
        frame.drawCalls != passDraws ||
        frame.triangles <= 0 ||
        frame.pipelineSwitches <= 0 ||
        frame.cpuMicros < frame.submitMicros) {
      throw StateError('the frame counters do not describe the rendered scene');
    }
    // #endregion check
  }
}
