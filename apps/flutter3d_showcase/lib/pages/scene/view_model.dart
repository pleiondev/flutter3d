/// A held item drawn in its own pass, over the finished world.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ViewModelDemo extends ShowcaseDemo {
  double fovDegrees = 48.0;
  double _bob = 0.0;

  late final CameraNode _handCamera;
  late final MeshNode _tool;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.0
      ..pitch = 0.2
      ..yaw = 0.4;
  }

  @override
  Scene build(DemoContext context) {
    // #region world
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.58, 0.56, 0.52, 1.0),
      roughness: 0.82,
    );
    final Scene world = Scene()
      ..ambientColor = Vector3(0.4, 0.46, 0.6)
      ..ambientIntensity = 0.16
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 20, depth: 20).build(),
          ),
          stone.copy()..doubleSided = true,
          name: 'floor',
        ),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(1.4, 2.4, 1.4)).build(),
          ),
          stone,
          name: 'pillar',
        )..setPosition(0.0, 1.2, -3.0),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -0.8, -0.3)),
      );
    // #endregion world

    // #region hands
    final Scene handsScene = Scene()
      ..add(
        _tool = MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(0.12, 0.12, 0.6)).build(),
          ),
          Material(
            name: 'tool',
            baseColor: Vector4(0.66, 0.68, 0.72, 1.0),
            metallic: 0.85,
            roughness: 0.28,
          ),
          name: 'held tool',
        )..setPosition(0.22, -0.2, -0.5),
      )
      ..add(
        LightNode(name: 'hand key', intensity: 2.6)
          ..setLocalForward(Vector3(-0.3, -0.5, -0.8)),
      );
    _handCamera = CameraNode(
      name: 'hand camera',
      projection: PerspectiveProjection(
        fovYRadians: fovDegrees * math.pi / 180.0,
      ),
    );
    handsScene.add(_handCamera);
    // #endregion hands

    // #region pass
    context.renderer.addNode(
      ViewModelNode(scene: handsScene, camera: _handCamera),
    );
    // #endregion pass
    return world;
  }

  @override
  void update(DemoContext context, double dt) {
    // #region motion
    _bob += dt;
    _tool.setPosition(0.22, -0.2 + math.sin(_bob * 2.4) * 0.02, -0.5);
    _handCamera.projection = PerspectiveProjection(
      fovYRadians: fovDegrees * math.pi / 180.0,
    );
    // #endregion motion
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Hand field of view',
      min: 25,
      max: 90,
      value: () => fovDegrees,
      onChanged: (double value) => fovDegrees = value,
      format: (double value) => '${value.round()} deg',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final bool viewModelRan = frame.passes.any(
      (FramePass pass) => pass.name == 'view model',
    );
    if (!viewModelRan || frame.drawCalls < 2) {
      throw StateError('the view model pass did not draw over the world');
    }
    // #endregion check
  }
}
