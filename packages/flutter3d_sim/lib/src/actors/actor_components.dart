/// What an actor is made of, one component at a time.
///
/// ## What moved, and what did not
///
/// The state moved. `Actor` used to hold the body, the health, the facing and
/// the brain as fields; they are components now, which means `EcsWorld.save()`
/// writes them and **refuses to write a component nobody registered**. That is
/// the whole reason for the move, and it is the only reason claimed.
///
/// The *handle* did not move, and could not. `Collider.userData` answers "who
/// is this" and callers ask it `is Damageable`, `is Rider`, `is Collector` —
/// one question with one answer, which replaced two type-switches over
/// concrete classes earlier in this project's life. An entity id in that field
/// would turn every one of those questions back into "look up a component in
/// which world", in the blast resolver, the hitscan, the mechanisms and the
/// pickups. So `Actor` survives as a thin thing that knows its entity and
/// answers those questions; every field on it is now a component read.
///
/// ## What the game gets that it did not have
///
/// Its own components on the same entity. A stealth game adds `Suspicion`, a
/// looter adds `Drops`, and neither needs a subclass of anything or a parallel
/// map keyed by actor. They register a codec and their state is in the save
/// file with everything else.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:vector_math/vector_math.dart';

import '../ecs/ecs_world.dart';
import 'blackboard.dart';
import 'brain.dart';
import 'health.dart';

/// The capsule that walks, slides along walls and falls off ledges.
final class Body {
  Body(this.controller);
  final CharacterController controller;
}

/// Health that can run out.
final class Vitality {
  Vitality(this.health);
  final Health health;
}

/// Which way it faces, how fast it comes round, and where its eye sits.
final class Facing {
  Facing({this.yaw = 0.0, this.turnRate = 6.0, this.eyeFraction = 0.32});

  /// Radians about Y. Zero looks along −Z.
  double yaw;

  /// Radians a second.
  double turnRate;

  /// Where the eye sits, as a fraction of the body's half-height above its
  /// centre. Roughly the chest on anything humanoid, which is what a shot
  /// should leave from and what a shot should aim at.
  double eyeFraction;
}

/// A body the world pushes around: a crate, a barrel, anything with mass.
///
/// Not [Body], which is a `CharacterController` — something driven by a brain
/// or by a player and never moved by physics. A `Physical` is the other kind:
/// nothing decides for it, and everything happens to it.
final class Physical {
  Physical(this.body);
  final RigidBody body;
}

/// How its body moved this step, for the view: what a stair climbed and
/// whether it stands on something.
///
/// **Published and never saved.** It reads the [CharacterController] it was
/// made with each time it is written, so there is nothing of its own to put
/// back; [registerActorComponents] registers it published and excludes it
/// from the save, which therefore writes the bytes it always did. Set on
/// every actor with a body by `ActorSystem.spawn`.
final class Gait {
  Gait(this.controller);
  final CharacterController controller;
}

/// What decides where it is going.
final class Thinking {
  Thinking(this.brain);
  Brain brain;
}

/// How each of an actor's components is written down: the codecs
/// [registerActorComponents] registers, here by name so a view reading
/// [PublishedState] can find an actor's rows by them.
abstract final class ActorCodecs {
  /// The capsule's state as `CharacterController.save` writes it: `at`, its
  /// centre in the simulation's local frame, `velocity` and the rest.
  /// Restored in place: the controller owns a collider in a live world.
  static final InPlaceCodec<Body> body = InPlaceCodec<Body>.of(
    id: 'body',
    encode: (value) => value.controller.save(),
    restore: (value, data, _) {
      if (data is Map) value.controller.restore(data.cast<String, Object?>());
    },
  );

  /// The health as `Health.save` writes it: `current`, `armour`, `mourned`.
  static final InPlaceCodec<Vitality> vitality = InPlaceCodec<Vitality>.of(
    id: 'vitality',
    encode: (value) => value.health.save(),
    restore: (value, data, _) {
      if (data is Map) value.health.restore(data.cast<String, Object?>());
    },
  );

  /// The facing: `yaw`, `turnRate`, `eyeFraction`.
  static final ComponentCodec<Facing> facing = ComponentCodec<Facing>.of(
    id: 'facing',
    encode: (value) => <String, Object?>{
      'yaw': value.yaw,
      'turnRate': value.turnRate,
      'eyeFraction': value.eyeFraction,
    },
    decode: (data, _) {
      if (data is! Map) return null;
      final row = data.cast<String, Object?>();
      return Facing(
        yaw: (row['yaw'] as num?)?.toDouble() ?? 0.0,
        turnRate: (row['turnRate'] as num?)?.toDouble() ?? 6.0,
        eyeFraction: (row['eyeFraction'] as num?)?.toDouble() ?? 0.32,
      );
    },
  );

  /// The rigid body, as `RigidBody.save` writes it. Restored in place.
  static final InPlaceCodec<Physical> physical = InPlaceCodec<Physical>.of(
    id: 'physical',
    encode: (value) => value.body.save(),
    restore: (value, data, _) {
      if (data is Map) value.body.restore(data.cast<String, Object?>());
    },
  );

  /// How the body moved this step: `steppedUp`, the height of the stair it
  /// climbed in metres, and `grounded`. In place and never restored: it is
  /// read off the body, which the body's own codec restores.
  static final InPlaceCodec<Gait> gait = InPlaceCodec<Gait>.of(
    id: 'gait',
    encode: (value) => <String, Object?>{
      'steppedUp': value.controller.steppedUp,
      'grounded': value.controller.isGrounded,
    },
    restore: (_, _, _) {},
  );

  /// The brain's own state. Restored in place: a brain is code as much as
  /// data.
  static final InPlaceCodec<Thinking> thinking = InPlaceCodec<Thinking>.of(
    id: 'thinking',
    encode: (value) => value.brain.save(),
    restore: (value, data, _) {
      if (data is Map) value.brain.restore(data.cast<String, Object?>());
    },
  );
}

/// Teaches an [EcsWorld] how to write an actor down.
///
/// Three of the five are registered **in place**: a `CharacterController`
/// owns a collider in a live collision world and a `Brain` is code as much
/// as data, so neither can be rebuilt from a file. Neither needs to be — a
/// snapshot restores a world that already exists — and the alternative,
/// declaring them unsaved and writing their numbers by hand somewhere else,
/// is the hand-written save this whole exercise removes, wearing a different
/// hat.
///
/// **The body, the health and the facing are published** (item 19): the
/// world the actors live in is the loop's, or one a genre adds to the loop's
/// `PublishedWorlds`, and the view reads where each one is, which way it
/// faces and whether it lives from `PublishedState` ([PublishedActor.read])
/// rather than from the actor. **The [Gait] is published and not saved**:
/// the stair a body climbed is the view's to smooth, and nothing a step
/// reads, so a save and its digest stay what they were.
///
/// A game adding its own component to an actor registers its codec the same
/// way, through `entities.components`.
void registerActorComponents(EcsWorld entities) {
  entities.components
    ..register<Body>(ActorCodecs.body, published: true)
    ..register<Vitality>(ActorCodecs.vitality, published: true)
    ..register<Facing>(ActorCodecs.facing, published: true)
    ..register<Physical>(ActorCodecs.physical)
    ..register<Thinking>(ActorCodecs.thinking)
    ..register<Gait>(ActorCodecs.gait, published: true)
    ..exclude<Gait>(
      'read off the body every time it is written; the view smooths a '
      'climbed stair with it and no step reads it',
    );
  // With the rest, so that a behaviour tree's state is in the save of any
  // world an actor system stands on, whoever made the world.
  registerBlackboard(entities);
}

/// An actor as the view reads it from [PublishedState]: where it is, which
/// way it faces, whether it lives — decoded from the rows its published
/// components ([ActorCodecs.body], [ActorCodecs.facing],
/// [ActorCodecs.vitality]) left for the step.
///
/// **The view's side of the boundary** (decision A of
/// `tasks/1.0-arch-review.md`): plain numbers copied out of a step, so a
/// renderer drawing from this keeps drawing when the simulation moves into
/// another isolate. [at] is in the simulation's local frame, relative to
/// [PublishedState.origin]; [worldAt] adds the two in double precision.
final class PublishedActor {
  const PublishedActor({
    required this.at,
    required this.yaw,
    required this.isAlive,
    required this.origin,
    this.steppedUp = 0.0,
    this.isGrounded = true,
  });

  /// [entity]'s published body, facing and health in [state]; null when it
  /// published no body (absent) — an actor that does not walk, or one whose
  /// world nothing publishes.
  static PublishedActor? read(PublishedState state, Entity entity) {
    final body = state.components[ActorCodecs.body.id]?[entity];
    if (body is! Map) return null;
    final at = Vector3.zero();
    if (!readVector(body['at'], at)) return null;
    final facing = state.read<Facing>(ActorCodecs.facing, entity);
    final health = state.components[ActorCodecs.vitality.id]?[entity];
    final current = health is Map ? health['current'] : null;
    final gait = state.components[ActorCodecs.gait.id]?[entity];
    return PublishedActor(
      at: at,
      yaw: facing?.yaw ?? 0.0,
      isAlive: current is! num || current > 0.0,
      origin: state.origin,
      steppedUp: switch (gait) {
        {'steppedUp': final num up} => up.toDouble(),
        _ => 0.0,
      },
      isGrounded: switch (gait) {
        {'grounded': final bool grounded} => grounded,
        _ => true,
      },
    );
  }

  /// The body's centre in the simulation's local frame.
  final Vector3 at;

  /// Radians about Y. Zero looks along −Z.
  final double yaw;

  /// Whether its health is above nought, or it has none.
  final bool isAlive;

  /// How high a stair its body climbed in the step, in metres: what the view
  /// smooths a staircase with. Nought when it climbed none, or published no
  /// [Gait].
  final double steppedUp;

  /// Whether its body stood on something after the step; true when it
  /// published no [Gait].
  final bool isGrounded;

  /// The floating origin [at] is relative to.
  final WorldPosition origin;

  /// [at] as a place in the world, in double precision.
  WorldPosition get worldAt => origin.translated(at.x, at.y, at.z);
}
