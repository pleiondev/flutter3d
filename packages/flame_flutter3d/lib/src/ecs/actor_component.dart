/// [ActorComponent] bridges one flutter3d_sim [Actor] to Flame — the
/// actor's simulated body kept in step with the [SceneNode] a game draws it
/// as.
library;

import 'package:flame/components.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import '../transform/object3d_component.dart';
import '../transform/plane.dart';

/// A Flame [PositionComponent] wrapping one flutter3d_sim [Actor] — the
/// same [SceneNode]/[BridgePlane] bridge [Object3dComponent] gives every
/// other bridged transform, plus the one extra hop an actor needs: its
/// body's simulated position lives on a [CharacterController], not on
/// [node].
///
/// **Why [direction] defaults to [SyncDirection.sceneToFlame].** An actor's
/// body is stepped by [ActorSystem.step] — run once a frame by
/// [ActorSystemComponent], never by this component — and that step is
/// scene-authoritative in exactly the sense [SyncDirection]'s own doc
/// already names it: nothing about a Flame position feeds back into it.
/// The rare game that drives an actor's body from a Flame-side animation
/// instead can still pass [SyncDirection.flameToScene] explicitly; this
/// default is only a default.
///
/// **Why [update] copies [Actor.body]'s position onto [node] before calling
/// `super.update`.** [Object3dComponent.update] reads `node.readPosition()`
/// — it has never heard of an [Actor], and should not have to, or every
/// bridge component in this package would need to know about every other
/// one's data model. The position [ActorSystem.step] just computed lives on
/// the [CharacterController] itself, so getting it onto the Flame side
/// means getting it onto [node] first. It is the same "sync the visual
/// thing from the real body" step `apps/flutter3d_showcase`'s rigid-body
/// demo already does by hand for a crate (`mesh.setPositionFrom(_crate
/// .position)`), done here once so every actor in a bridged game gets it
/// for free instead of every game re-deriving it.
///
/// **Why a despawned actor needs no special case in [onRemove].** This
/// class does not override it: [Object3dComponent.onRemove] detaches
/// [node] unconditionally, and [node] has its own lifetime independent of
/// [actor] — an actor going away does not reach back and clear its scene
/// node's parent pointer. Nothing here reads [Actor.exists] because nothing
/// here needs to: [Actor.body] already answers `null` for a despawned
/// entity (`EcsWorld.get` does, by construction, once the entity's
/// generation has moved on), so the null check already in [update] is the
/// only guard a despawned actor ever required.
final class ActorComponent extends Object3dComponent {
  ActorComponent({
    required this.actor,
    required super.node,
    required super.scene,
    required super.plane,
    super.direction = SyncDirection.sceneToFlame,
    super.elevation,
    super.position,
    super.size,
    super.anchor,
    super.angle,
    super.scale,
    super.children,
    super.priority,
    super.key,
  });

  /// The flutter3d_sim actor this component bridges to Flame.
  final Actor actor;

  /// Copies the actor's body and facing onto [node], then lets
  /// [Object3dComponent.update] read them onto the Flame side.
  ///
  /// **Only when the scene is authoritative.** Flowing Flame to the scene,
  /// the node is written from Flame's position straight after, and copying
  /// the body there first did nothing but cost a write.
  ///
  /// **The facing too, not only the place.** An actor turns by its yaw,
  /// radians about Y with nought looking along −Z, which is the rotation a
  /// node is drawn with; without it every bridged actor slid about facing
  /// the one way it was built facing.
  @override
  void update(double dt) {
    if (direction == SyncDirection.sceneToFlame) {
      final body = actor.body;
      // Null for an actor with no body (a turret, a director) and for one
      // that has been despawned — both are "nothing to copy", not an error.
      if (body != null) node.setPositionFrom(body.position);
      if (actor.facing != null) {
        node.setRotation(Quaternion.axisAngle(_up, actor.yaw));
      }
    }
    super.update(dt);
  }

  static Vector3 get _up => Vector3(0.0, 1.0, 0.0);
}
