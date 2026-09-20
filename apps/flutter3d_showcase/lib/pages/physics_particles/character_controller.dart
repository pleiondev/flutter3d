/// A capsule-shaped walker, dropped onto a floor and pushed sideways,
/// stepped by hand a few dozen times rather than once, so it actually lands.
/// The collider stays the plain box `CharacterController` gives one by
/// default — see `character_controller.md` for why — but what stands on it
/// is `RobotExpressive.glb` rather than the crate that used to mark its
/// place, so a reader watches an actual character land and walk.
///
/// Quoted by `character_controller.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class CharacterControllerDemo extends ShowcaseDemo {
  late final CollisionWorld _world;
  late final CharacterController _controller;
  late final ModelAsset _asset;
  ModelInstance? _model;

  static const double _step = 1 / 60;
  static const int _steps = 90;

  /// `RobotExpressive.glb` stands this tall in its own file — measured once,
  /// off the mesh it ships with — so [_characterHeight] can scale it to the
  /// collider's own box without carrying a decoded model around just to ask.
  static const double _modelHeight = 4.461221901699901;

  /// What the collider's box already claimed: `CharacterController`'s
  /// default shape is `CollisionBox(Vector3(0.35, 0.9, 0.35))`, 1.8 m tall.
  static const double _characterHeight = 1.8;

  @override
  void configureView(DemoContext context) {
    // Distance and target are set again in `build`, once the walk has run
    // and there is somewhere to actually point the camera at.
    context.orbit
      ..pitch = 0.2
      ..yaw = 0.6;
  }

  @override
  Future<void> prepare(DemoContext context) async {
    // #region model
    // CC0 — Tomás Laulhé, with facial morph targets by Don McCurdy; see
    // `packages/flutter3d_samples/assets/ATTRIBUTION.md`. Fourteen clips ship
    // in the one file, and "Walking" is the one this page plays.
    final document = await loadModelByPath(
      'packages/flutter3d_samples/assets/RobotExpressive.glb',
    );
    _asset = await ModelAsset.fromDocument(document, device: context.device);
    // #endregion model
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

    // The walk covers several metres of +x, and `configureView` runs before
    // any of it — orbiting the origin left the walker's actual resting place
    // well outside the frame. This page draws a single, already-landed
    // frame rather than the walk itself, so what needs framing is where the
    // walker actually ended up, not where it started.
    context.orbit
      ..target.setValues(_controller.position.x, 0.9, 0.0)
      ..distance = 5.0
      ..apply();

    final Scene scene = Scene()
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
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );

    // #region body
    // The model's own origin sits at its feet, not its centre, and it faces
    // +Z at rest; turned a quarter-turn around Y so it faces the +X the walk
    // above actually carried it towards, then dropped onto the box's own
    // centre minus half its height, the ground the box already stands on.
    final ModelInstance model = _model = _asset.instantiate(
      scene,
      name: 'walker',
    );
    final double scale = _characterHeight / _modelHeight;
    model.root
      ..setScale(scale, scale, scale)
      ..setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), -math.pi / 2));
    model.player?.playNamed('Walking');
    // #endregion body

    _placeModel();
    return scene;
  }

  void _placeModel() {
    final ModelInstance? model = _model;
    if (model == null) return;
    final Vector3 position = _controller.position;
    final double feetY = position.y - _controller.halfExtents.y;
    model.root.setPosition(position.x, feetY, position.z);
  }

  @override
  void update(DemoContext context, double dt) {
    _placeModel();
    _model?.player?.update(dt);
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
    if (_model == null || _model!.meshes.isEmpty) {
      throw StateError('the model did not reach the scene');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the walker did not reach the frame');
    }
  }
}
