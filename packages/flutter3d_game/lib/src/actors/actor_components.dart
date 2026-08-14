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

import '../ecs/ecs_world.dart';
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

/// What decides where it is going.
final class Thinking {
  Thinking(this.brain);
  Brain brain;
}

/// Teaches an [EcsWorld] how to write an actor down.
///
/// Two of the four are registered **in place**: a `CharacterController` owns a
/// collider in a live collision world and a `Brain` is code as much as data, so
/// neither can be rebuilt from a file. Neither needs to be — a snapshot
/// restores a world that already exists — and the alternative, declaring them
/// unsaved and writing their numbers by hand somewhere else, is the
/// hand-written save this whole exercise removes, wearing a different hat.
///
/// A game adding its own component to an actor calls the same methods for it.
void registerActorComponents(EcsWorld entities) {
  entities
    ..registerInPlace<Body>(
      'body',
      encode: (Body value) => value.controller.save(),
      restore: (Body value, Object? data) {
        if (data is Map) value.controller.restore(data.cast<String, Object?>());
      },
    )
    ..registerInPlace<Vitality>(
      'vitality',
      encode: (Vitality value) => value.health.save(),
      restore: (Vitality value, Object? data) {
        if (data is Map) value.health.restore(data.cast<String, Object?>());
      },
    )
    ..register<Facing>(
      'facing',
      encode: (Facing value) => <String, Object?>{
        'yaw': value.yaw,
        'turnRate': value.turnRate,
        'eyeFraction': value.eyeFraction,
      },
      decode: (Object? data) {
        final row = (data! as Map).cast<String, Object?>();
        return Facing(
          yaw: (row['yaw'] as num?)?.toDouble() ?? 0.0,
          turnRate: (row['turnRate'] as num?)?.toDouble() ?? 6.0,
          eyeFraction: (row['eyeFraction'] as num?)?.toDouble() ?? 0.32,
        );
      },
    )
    ..registerInPlace<Thinking>(
      'thinking',
      encode: (Thinking value) => value.brain.save(),
      restore: (Thinking value, Object? data) {
        if (data is Map) value.brain.restore(data.cast<String, Object?>());
      },
    );
}
