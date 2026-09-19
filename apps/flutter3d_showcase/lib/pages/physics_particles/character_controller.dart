/// A capsule-shaped walker, dropped onto a floor and pushed sideways,
/// stepped by hand a few dozen times rather than once, so it actually lands.
///
/// Quoted by `character_controller.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class CharacterControllerDemo extends ShowcaseDemo {
  late final CollisionWorld _world;
  late final CharacterController _controller;
  late final MeshNode _body;

  static const double _step = 1 / 60;
  static const int _steps = 90;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.0
      ..pitch = 0.2
      ..yaw = 0.6;
  }

  @override
  Scene build(DemoContext context) {
    // #region floor
    _world = CollisionWorld();
    _world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
    // #endregion floor

    // #region controller
    _controller = CharacterController(
      world: _world,
      position: Vector3(0.0, 3.0, 0.0),
    );
    // #endregion controller

    // #region walk
    // Stepped by hand, at a fixed rate, so the same run always lands the
    // same way. A real game calls this once a frame with the frame's own
    // wish direction; a page rendered once has to do all its steps up front.
    for (var i = 0; i < _steps; i++) {
      _controller.step(_step, wishDirection: Vector3(1.0, 0.0, 0.0));
    }
    // #endregion walk

    _body = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(0.7, 1.8, 0.7)).build(),
      ),
      Material(name: 'walker', baseColor: Vector4(0.8, 0.5, 0.3, 1.0)),
      name: 'walker',
    )..setPositionFrom(_controller.position);

    return Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(20.0, 1.0, 20.0)).build(),
          ),
          Material(name: 'floor', baseColor: Vector4(0.5, 0.55, 0.5, 1.0)),
          name: 'floor',
        )..setPosition(0.0, -0.5, 0.0),
      )
      ..add(_body)
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    _body.setPositionFrom(_controller.position);
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (!_controller.isGrounded) {
      throw StateError('the walker should have landed by now');
    }
    if (_controller.groundNormal.y < 0.99) {
      throw StateError('a flat floor should read as a flat ground normal');
    }
    if (_controller.position.x <= 0.0) {
      throw StateError('the walker should have moved towards +x');
    }
    // #endregion check
    if (frame.drawCalls < 1) {
      throw StateError('the walker did not reach the frame');
    }
  }
}
