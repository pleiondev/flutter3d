/// A physics-authoritative [RigidBody] kept at the same place as a flutter3d
/// [SceneNode] and a Flame [PositionComponent].
library;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_physics/flutter3d_physics.dart';

import '../transform/object3d_component.dart';

/// Bridges one [RigidBody] onto a flutter3d [SceneNode] and, through
/// [Object3dComponent], onto a Flame [PositionComponent] — and, through the
/// [CollisionCallbacks] this mixes in, onto the method surface
/// [CollisionBridge] relays flutter3d's own collision events into.
///
/// **[body] is built and stepped elsewhere.** Constructing a [RigidBody]
/// already adds it to the [CollisionWorld] it names, and almost every caller
/// also hands it to a [Dynamics] the way `Dynamics.add` wants — so by the
/// time a [RigidBodyComponent] wraps one, both have very likely already
/// happened. This component never calls `Dynamics.step` itself: exactly one
/// thing should step a shared simulation once a frame, the way a single
/// `ActorSystemComponent` would centralize `ActorSystem.step` rather than
/// letting every actor-bridging component step its own copy — a hundred
/// `RigidBodyComponent`s each stepping the same `Dynamics` is a hundred steps
/// a frame, and the bug that produces is "everything moves too fast," which
/// is a strange place to have to go looking for "a component and a game loop
/// both call step."
///
/// **Defaults to [SyncDirection.sceneToFlame].** [SyncDirection]'s own doc
/// comment already says a rigid body is scene-authoritative: the solver
/// decides where it is, and Flame's `position` is a read of that decision,
/// never a write into it. A caller that truly wants a Flame-driven body — an
/// input-controlled crate, say — should not reach for this component at all;
/// nothing here supports writing a Flame position back onto a [RigidBody]'s
/// [Collider], because [Collider.moveTo] is [Dynamics]'s to call, not a
/// transform bridge's.
class RigidBodyComponent extends Object3dComponent with CollisionCallbacks {
  RigidBodyComponent({
    required this.body,
    required super.node,
    required super.scene,
    required super.plane,
    super.direction,
    super.position,
    super.angle,
    super.scale,
    super.children,
    super.priority,
    super.key,
  });

  /// The physics body this component tracks.
  ///
  /// Owned by whoever built it — this component neither constructs the body
  /// nor removes it from its [CollisionWorld]; it only reads
  /// [RigidBody.position] every frame.
  final RigidBody body;

  /// Copies [body]'s current position onto [node], then defers to
  /// [Object3dComponent.update] to carry that onto the Flame side.
  ///
  /// The same line every current caller of `flutter3d_physics` already
  /// writes by hand — `mesh.setPositionFrom(body.position)` in
  /// `apps/flutter3d_showcase/lib/pages/physics_particles/rigid_bodies.dart`
  /// — generalized once here so a Flame-bridged body does not need a
  /// bespoke per-frame update to stay honest about where its physics really
  /// put it.
  @override
  void update(double dt) {
    node.setPositionFrom(body.position);
    super.update(dt);
  }
}
