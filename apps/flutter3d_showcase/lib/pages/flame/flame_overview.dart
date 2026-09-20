/// Flame's own layer and flutter3d's own layer, drawn side by side and not
/// yet talking to each other — the state every other page in this category
/// starts connecting.
///
/// Quoted by `flame_overview.md` and shown whole in the Source tab.
library;

import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_flame/flutter3d_flame.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class FlameOverviewDemo extends ShowcaseDemo {
  late final double _flameX;
  late final double _cubeX;

  @override
  Scene build(DemoContext context) {
    final (double flameX, double cubeX) = _run();
    _flameX = flameX;
    _cubeX = cubeX;

    final material = Material(
      name: 'cube',
      baseColor: Vector4(0.5, 0.6, 0.8, 1.0),
    );
    final node = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(0.8, 0.8, 0.8)).build(),
      ),
      material,
      name: 'cube',
    );

    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );
  }

  static (double, double) _run() {
    // #region flame-layer
    // Flame's own layer: a plain PositionComponent, the same class every
    // sprite and shape in a Flame game already is. Nothing here has heard of
    // flutter3d.
    final flameShape = PositionComponent(position: Vector2(2.0, 0.0));
    // #endregion flame-layer

    // #region flutter3d-layer
    // flutter3d's own layer: a cube placed at a spot of its own, on the far
    // side of the origin from the Flame shape. Nothing here has heard of
    // Flame.
    const double cubeX = 9.0;
    // #endregion flutter3d-layer

    // #region unconnected
    // Ticking the Flame side does not move it towards the cube, and moving
    // the cube (above) never touched the Flame shape at all: no bridge sits
    // between them yet. That is every other page in this category, one
    // mechanism at a time.
    flameShape.update(1 / 60);
    final double flameX = flameShape.position.x;
    // #endregion unconnected

    return (flameX, cubeX);
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) {
    final scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(0.8, 0.8, 0.8)).build(),
          ),
          Material(name: 'cube', baseColor: Vector4(0.5, 0.6, 0.8, 1.0)),
          name: 'cube',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );
    final game = TransparentFlameGame()
      ..add(
        RectangleComponent(
          position: Vector2(24, 24),
          size: Vector2(48, 48),
          paint: Paint()..color = const Color(0xFFE8A33D),
        ),
      );
    return Flutter3dFlameWidget(
      game: game,
      camera: CameraNode(name: 'overview-preview'),
      existing: (device: context.device, renderer: context.renderer),
      buildScene: (GraphicsDevice device) => scene,
    );
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the cube marker was not drawn');
    }
    if (_flameX != 2.0) {
      throw StateError(
        'the Flame shape should not have moved on its own, got $_flameX',
      );
    }
    if (_cubeX != 9.0) {
      throw StateError('the flutter3d cube should be at its own spot');
    }
  }
}
