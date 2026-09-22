/// A large scene where most mesh boxes sit outside the current frustum.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class CullingDemo extends ShowcaseDemo {
  static const int visibleCount = 16;
  static const int hiddenCount = 304;

  late final SceneNode _offscreenBranch;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 12.0
      ..pitch = 0.42
      ..yaw = 0.55;
  }

  @override
  Scene build(DemoContext context) {
    final DeviceMesh cube = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3.all(0.72)).build(),
    );
    final Material material = Material(
      name: 'culling markers',
      baseColor: Vector4(0.25, 0.62, 0.86, 1.0),
      roughness: 0.58,
    );

    // #region visible
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.44, 0.53, 0.7)
      ..ambientIntensity = 0.14;
    for (var i = 0; i < visibleCount; i++) {
      final int x = i % 4;
      final int z = i ~/ 4;
      scene.add(
        MeshNode(cube, material, name: 'visible cube $i')
          ..setPosition((x - 1.5) * 1.35, 0.0, (z - 1.5) * 1.35),
      );
    }
    // #endregion visible

    // #region offscreen
    _offscreenBranch = SceneNode(name: 'offscreen warehouse')
      ..setPosition(120.0, 0.0, 80.0);
    for (var i = 0; i < hiddenCount; i++) {
      final int x = i % 19;
      final int z = i ~/ 19;
      _offscreenBranch.add(
        MeshNode(cube, material, name: 'offscreen cube $i')
          ..setPosition(x * 1.1, 0.0, z * 1.1),
      );
    }
    scene.add(_offscreenBranch);
    // #endregion offscreen

    // #region light
    scene.add(
      LightNode(name: 'sun', intensity: 3.1)
        ..setLocalForward(Vector3(-0.5, -0.8, -0.3)),
    );
    // #endregion light
    return scene;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final int total = visibleCount + hiddenCount;
    if (scene.meshes.length != total ||
        _offscreenBranch.subtreeBounds == null ||
        frame.culled < hiddenCount ||
        frame.drawCalls < visibleCount) {
      throw StateError('the offscreen mesh field was not culled');
    }
    // #endregion check
  }
}
