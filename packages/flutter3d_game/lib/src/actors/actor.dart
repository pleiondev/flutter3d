/// Who a collider is, and the way into what it is made of.
///
/// ## A handle, not the state
///
/// The body, the health, the facing and the brain are components on an entity
/// — see `actor_components.dart` for what that bought. This is what is left:
/// an entity id, the world it is in, and the answers to the three questions
/// anything that hits a collider asks it.
///
/// It could not be dissolved entirely, and the reason is worth stating rather
/// than working around. `Collider.userData` answers *who is this*, and callers
/// ask `is Damageable`, `is Rider`, `is Collector`. Those replaced two
/// type-switches over concrete classes, and putting an entity id in that field
/// would turn each of them back into "look up a component, in which world" —
/// in the blast resolver, the hitscan, the mechanisms and the pickups. One
/// small object per actor is cheaper than that, and honest about what it is.
///
/// What is *not* here any more, and is the clearest sign the move was real:
/// `ordinal`. Actors were numbered by hand so that thinking could be staggered
/// deterministically across steps; an entity already has a stable index, so the
/// field and the line that set it are both gone.
library;

import 'package:vector_math/vector_math.dart';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import '../ecs/ecs_world.dart';
import '../ecs/entity.dart';
import '../world/rider.dart';
import 'actor_components.dart';
import 'brain.dart';
import 'damageable.dart';
import 'health.dart';

final class Actor implements Damageable, Rider {
  /// Made by [ActorSystem.spawn] and nowhere else.
  ///
  /// One handle per entity, kept by the system, because [onDamage] is on it: a
  /// second handle made on the side would answer every question correctly and
  /// route damage past the thing that counts deaths.
  Actor(this.entities, this.entity);

  final EcsWorld entities;
  final Entity entity;

  /// Which actor this is, for anything that needs a stable order.
  ///
  /// The entity's own index: unique among the living, the same on two runs of
  /// the same game, and nobody has to remember to assign it.
  int get ordinal => entity.index;

  bool get exists => entities.alive(entity);

  CharacterController get body => entities.get<Body>(entity)!.controller;

  Health get health => entities.get<Vitality>(entity)!.health;

  Facing get facing => entities.get<Facing>(entity)!;

  Brain get brain => entities.get<Thinking>(entity)!.brain;
  set brain(Brain value) => entities.get<Thinking>(entity)!.brain = value;

  double get yaw => facing.yaw;
  set yaw(double value) => facing.yaw = value;

  double get turnRate => facing.turnRate;

  /// Installed by the system, so that being hurt goes through the system that
  /// counts deaths and stops corpses blocking corridors.
  ///
  /// A closure rather than a reference to the system, because that file already
  /// imports this one and naming it here would close a cycle.
  bool Function(double amount)? onDamage;

  @override
  bool applyDamage(double amount) =>
      onDamage?.call(amount) ?? health.damage(amount);

  @override
  Collider? get carriedBy => body.groundBody;

  Vector3 get position => body.position;

  bool get isAlive => health.isAlive;

  /// Where a shot from this actor leaves, and where a shot at it should aim.
  Vector3 eyeLevel(Vector3 out) => out
    ..setFrom(body.position)
    ..y += body.halfExtents.y * facing.eyeFraction;

  /// Two handles to the same entity are the same actor.
  ///
  /// They are made freshly on every lookup, so identity has to be the entity's
  /// rather than the object's — otherwise `identical(target, player)` and every
  /// `Map<Actor, …>` in a renderer quietly stop working.
  @override
  bool operator ==(Object other) =>
      other is Actor && other.entity == entity && other.entities == entities;

  @override
  int get hashCode => entity.hashCode;
}
