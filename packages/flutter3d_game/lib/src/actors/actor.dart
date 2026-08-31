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
///
/// ## Everything is optional
///
/// Every accessor below is nullable, and that is deliberate rather than
/// defensive. `spawn` used to require a body, health and a brain, so a turret
/// that does not walk, a barrel that does not think and a hazard with no health
/// all had to carry components they never used — which is precisely what an
/// entity-component design exists to stop. An entity has what it needs; the
/// systems ask.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

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

  /// The capsule that walks, or null for something that does not.
  ///
  /// **Nullable, and that is the whole shape of this class.** A turret does not
  /// walk. A destructible barrel does not walk, does not think, and has no
  /// facing. An actor used to be forced to have all four components because
  /// `spawn` required them, which is the thing an entity-component design
  /// exists to stop: an entity has what it needs and the systems ask.
  CharacterController? get body => entities.get<Body>(entity)?.controller;

  /// Health, or null for something that cannot be hurt.
  Health? get health => entities.get<Vitality>(entity)?.health;

  /// Which way it faces, or null for something with no front.
  Facing? get facing => entities.get<Facing>(entity);

  /// What decides for it, or null for something driven by the game directly.
  Brain? get brain => entities.get<Thinking>(entity)?.brain;
  set brain(Brain? value) {
    if (value == null) {
      entities.remove<Thinking>(entity);
    } else {
      entities.set(entity, Thinking(value));
    }
  }

  double get yaw => facing?.yaw ?? 0.0;
  set yaw(double value) => facing?.yaw = value;

  double get turnRate => facing?.turnRate ?? 0.0;

  /// Installed by the system, so that being hurt goes through the system that
  /// counts deaths and stops corpses blocking corridors.
  ///
  /// A closure rather than a reference to the system, because that file already
  /// imports this one and naming it here would close a cycle.
  bool Function(double amount, Object? from)? onDamage;

  /// Takes damage, if there is anything here to hurt.
  ///
  /// False for an actor with no health — a moving platform's body, a scenery
  /// piece with a collider. **Not an error**: a rocket asks everything in its
  /// radius, and "nothing happened" is the honest answer for a lamp post.
  @override
  bool applyDamage(double amount, {Object? from}) {
    if (health == null) return false;
    return onDamage?.call(amount, from) ?? health!.damage(amount);
  }

  @override
  Collider? get carriedBy => body?.groundBody;

  /// Where it is, or null for an actor with no body.
  ///
  /// A game whose actors are not all bodies gives them a place of its own with
  /// its own component; the engine does not guess one.
  Vector3? get position => body?.position;

  /// True unless there is health here and it has run out.
  ///
  /// Something with no health is not dead — it is unkillable, which is what a
  /// lift and a lamp post are.
  bool get isAlive => health?.isAlive ?? true;

  /// Where a shot from this actor leaves, and where a shot at it should aim.
  ///
  /// False when there is no body to measure from, so a caller that assumed one
  /// finds out rather than aiming at the origin of the world.
  bool eyeLevel(Vector3 out) {
    final body = this.body;
    if (body == null) return false;
    out
      ..setFrom(body.position)
      ..y += body.halfExtents.y * (facing?.eyeFraction ?? 0.32);
    return true;
  }

  /// Where up the body [point] is: nought at the feet, one at the crown.
  ///
  /// **Geometry, and deliberately not anatomy.** Which fractions are a head, a
  /// chest or a knee is a genre's business — a shooter has hit zones and a
  /// platformer has none — and an engine that named them would be an engine
  /// written for one kind of game. What is here is the measurement every such
  /// table needs and none of them should do twice.
  ///
  /// Clamped, so a shot that grazes the very top or scuffs the floor under the
  /// feet still answers with something a table can be indexed by. Null when
  /// there is no body to measure against, which a caller must handle rather
  /// than treat as the middle.
  double? fractionUp(Vector3 point) {
    final body = this.body;
    if (body == null) return null;
    final half = body.halfExtents.y;
    if (half <= 0.0) return 0.5;
    final feet = body.position.y - half;
    return ((point.y - feet) / (half * 2.0)).clamp(0.0, 1.0);
  }

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
