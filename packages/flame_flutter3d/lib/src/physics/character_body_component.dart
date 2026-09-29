import 'package:flame/collisions.dart' show CollisionCallbacks;
import 'package:flutter3d_physics/flutter3d_physics.dart'
    show CharacterController;
import 'package:vector_math/vector_math.dart' show Vector3;

import '../host/has_fixed_step.dart';
import '../transform/object3d_component.dart';

/// A `CharacterController` with no actor round it, carried across the
/// bridge: the body a platformer's runner moves, Pitfall Harry's.
///
/// **What the platformer already has, reached from Flame.** A runner in
/// `flutter3d_game_platformer` runs, jumps twice, grabs ladders and ropes,
/// and moves a character controller; what it lacked on Flame's side was a
/// component that steps it with the game and puts it where it is. [drive]
/// is that step, `runner.step(dt, input)` say, and runs in the game's fixed
/// steps when the game has `HasFixedStep`, once a frame otherwise. The body's
/// place is written onto the node and read back to Flame, drawn between its
/// last two steps when the steps are fixed.
class CharacterBodyComponent extends Object3dComponent
    with CollisionCallbacks, FixedStepUpdate {
  CharacterBodyComponent({
    required this.body,
    required super.node,
    required super.scene,
    required super.plane,
    this.drive,
    super.size,
    super.anchor,
    super.priority,
  });

  /// The body being moved.
  final CharacterController body;

  /// What moves [body] by one step of the given seconds.
  final void Function(double dt)? drive;

  final Vector3 _before = Vector3.zero();
  final Vector3 _drawn = Vector3.zero();
  bool _stepped = false;

  @override
  void fixedUpdate(double step) {
    _before.setFrom(body.position);
    _stepped = true;
    drive?.call(step);
  }

  @override
  void update(double dt) {
    final game = findGame();
    if (game is! HasFixedStep) drive?.call(dt);
    if (game is HasFixedStep && _stepped) {
      Vector3.mix(_before, body.position, game.alpha, _drawn);
      placeNode(_drawn);
    } else {
      placeNode(body.position);
    }
    super.update(dt);
  }
}
