import 'package:flutter3d_physics/flutter3d_physics.dart';

import '../host/bridge_priority.dart';
import '../host/has_fixed_step.dart';
import '../transform/object3d_component.dart';

/// A collider Flame moves: a lift, an escalator's step, a platform on a
/// path, moved with Flame's own effects and carrying whoever stands on it.
///
/// **The other way round from `RigidBodyComponent`.** A rigid body is moved
/// by the solver and Flame reads where it went; a lift is moved by the game,
/// a `MoveEffect` up and down or a `MoveAlongPathEffect` round a loop, and
/// the world has to be told. Written into the collider by hand, the lift
/// moved and its passenger stayed where it was: a character is carried by
/// the motion `Collider.moveTo` records, and only by that.
///
/// So each step the collider is moved to where Flame has put this
/// component, through `moveTo`, and a step in which it did not move clears
/// what the last one recorded, so a passenger is carried once for each move
/// and not again on every step after it. The collider should be of
/// `ColliderKind.kinematic`. A conveyor's belt is `Collider.surfaceVelocity`,
/// set on it directly.
///
/// Updated before the actors and the physics
/// ([BridgePriority.kinematic]), in the game's steps when it has
/// `HasFixedStep`: a passenger stepped before its lift moved would stand a
/// step behind it. In such a game the lift follows where Flame put it the
/// frame before, since the steps run before this frame's effects.
class KinematicBodyComponent extends Object3dComponent with FixedStepUpdate {
  KinematicBodyComponent({
    required this.collider,
    required super.node,
    required super.scene,
    required super.plane,
    super.elevation,
    super.position,
    super.size,
    super.anchor,
    super.angle,
    super.children,
    super.priority = BridgePriority.kinematic,
    super.key,
  }) : super(direction: SyncDirection.flameToScene);

  /// What the world sees of this: moved to where Flame puts it.
  final Collider collider;

  bool _stepped = false;

  @override
  void onMount() {
    super.onMount();
    _stepped = findGame() is HasFixedStep;
  }

  @override
  void fixedUpdate(double step) => _carry();

  /// Moved once a frame, after the effects under it have, when the game
  /// has no fixed steps: before the physics and the actors, which are later
  /// siblings.
  @override
  void updateTree(double dt) {
    super.updateTree(dt);
    if (!_stepped) _carry();
  }

  void _carry() {
    final at = scenePosition;
    final now = collider.position;
    if (at.x == now.x && at.y == now.y && at.z == now.z) {
      collider.clearDelta();
    } else {
      collider.moveTo(at);
    }
  }
}
