import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import '../loop/game_event.dart';
import 'actor.dart';

/// An actor took damage this step and survived it.
///
/// A [GameEvent] rather than a value in a list beside one: this class already
/// carried everything an event carries, and having it be the event is what
/// stops the two from drifting.
final class ActorHurt extends GameEvent {
  ActorHurt(this.actor, this.amount, {this.from});

  /// The name it is declared and published under.
  static const String eventName = 'actor.hurt';

  /// Its codec: the actor's ordinal, the amount and whether it staggered.
  /// Written for a digest and a trace; it reads back as null, since an
  /// actor is a live part of a world and not a value.
  static final EventCodec<ActorHurt> codec = EventCodec<ActorHurt>.of(
    encode: (ActorHurt e) => <Object?>[e.actor.ordinal, e.amount, e.staggered],
    decode: (Object? data, int version) => null,
  );

  final Actor actor;

  /// The damage, in hit points, the game's own unit of `Health`.
  final double amount;

  /// Whoever dealt it, as the collider's `userData`, or null for damage with
  /// nobody behind it — a fall, a crushing lift, a pit.
  final Object? from;

  /// Whether it visibly reacted. Set by whatever decided that it did — a
  /// caller can tell a grunt from a scream.
  ///
  /// **Written after this is published**, by the brain that reacts to the
  /// damage later in the same step. That is safe because the engine's bus
  /// hands a step's events out at the step's end: a subscriber never sees
  /// this one before everything that had an opinion about it has spoken. A
  /// `DirectBus` hands it out at once, before then; the event is the same
  /// object, so it reads true once the step is over.
  bool staggered = false;

  @override
  String get name => eventName;
}

/// An actor's health reached zero this step.
///
/// One per actor, published where the death happens rather than collected
/// into a list read afterwards. The distinction is not academic: the list
/// this replaces was cleared at the top of `ActorSystem.step`, which is
/// halfway through a game's step, so a monster the player shot before the
/// actors thought was added and wiped again in the same step. Nothing
/// downstream ever saw it — no death sound, no sparks, no count.
final class ActorDied extends GameEvent {
  const ActorDied(this.actor, {this.from});

  /// The name it is declared and published under.
  static const String eventName = 'actor.died';

  /// Its codec: the actor's ordinal. Reads back as null, as [ActorHurt]'s.
  static final EventCodec<ActorDied> codec = EventCodec<ActorDied>.of(
    encode: (ActorDied e) => e.actor.ordinal,
    decode: (Object? data, int version) => null,
  );

  final Actor actor;

  /// Whoever killed it, as the collider's `userData`, or null for a death with
  /// nobody behind it.
  final Object? from;

  @override
  String get name => eventName;
}
