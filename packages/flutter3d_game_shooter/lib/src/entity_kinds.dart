import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'gift.dart';
import 'monsters.dart';
import 'pickup.dart';
import 'secret.dart';

/// The kinds of entity a shooter's levels contain beyond the format's own.
///
/// `EntityTypes` keeps the vocabulary true of any level whatever the game is —
/// a spawn point, a door, a lift, a button, a trigger, an exit, a light. What a
/// pickup gives, what a key unlocks and what a note says are this genre's, and
/// they left the format the day the format stopped being one game's.

final class PickupKind extends EntityKind {
  const PickupKind(this.gifts) : super(ShooterEntities.pickup);

  /// What a `gives` string may name, and what it grants.
  final GiftRegistry gifts;

  /// A panel of light on the floor, roughly the size of what it represents.
  static final Vector3 defaultSize = Vector3(0.45, 0.45, 0.45);

  /// What a document may ask for, taken from the registry rather than listed
  /// again here: two lists of the same names is one list too many.
  Iterable<String> get gives => gifts.names;

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final what = entity.string('gives');
    if (what == null) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'has no "gives", so picking it up would do nothing',
          where: scope.describe(entity),
        ),
      );
      return;
    }
    if (!gifts.knows(what)) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'gives "$what", which nothing knows how to grant',
          where: scope.describe(entity),
        ),
      );
    }
    final amount = entity.number('amount');
    if (amount != null && amount <= 0.0) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.warning,
          'gives an amount of $amount',
          where: scope.describe(entity),
        ),
      );
    }
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final gift = gifts[entity.string('gives') ?? ''];
    if (gift == null) return;
    final collider = place(
      entity,
      context,
      kind: ColliderKind.trigger,
      layer: CollisionLayers.pickup,
      mask: CollisionLayers.player,
      fallbackSize: defaultSize,
    );
    final pickup = context.mechanisms.add(
      Pickup(
        name: entity.name,
        gift: gift,
        amount: entity.number('amount') ?? gift.defaultAmount,
        detail: entity.string('color'),
        collider: collider,
      ),
    );
    context.reveal(
      entity,
      collider: collider,
      mechanism: pickup,
      size: entity.vector('size') ?? defaultSize,
    );
  }
}

/// Places a [Secret]: a trigger volume that is counted the first time somebody
/// walks into it.
///
/// No fields to validate — a secret is a place and nothing else. What is behind
/// it is whatever else the author put there, which is the whole idea: the
/// reward is the room, not the trigger.
final class SecretKind extends EntityKind {
  const SecretKind() : super(ShooterEntities.secret);

  /// Big enough to be walked into rather than stepped over, and no bigger: a
  /// secret the size of the room it is in would be found from the doorway.
  static final Vector3 defaultSize = Vector3(2.0, 2.5, 2.0);

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final collider = place(
      entity,
      context,
      kind: ColliderKind.trigger,
      layer: CollisionLayers.trigger,
      mask: CollisionLayers.player,
      fallbackSize: defaultSize,
    );
    context.mechanisms.add(Secret(name: entity.name, collider: collider));
    // Nothing is revealed: a secret a player can see is not one.
  }
}

final class KeyKind extends EntityKind {
  const KeyKind() : super(EntityTypes.key);

  /// Small enough to walk past without collecting by accident, big enough to
  /// walk into on purpose.
  static final Vector3 defaultSize = Vector3(0.4, 0.4, 0.4);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireText(entity, scope, out, 'color');
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final colour = entity.string('color');
    if (colour == null) return;
    final collider = place(
      entity,
      context,
      kind: ColliderKind.trigger,
      layer: CollisionLayers.pickup,
      mask: CollisionLayers.player,
      fallbackSize: defaultSize,
    );
    final pickup = context.mechanisms.add(
      Pickup(
        name: entity.name,
        gift: const KeyGift(),
        amount: 1.0,
        detail: colour,
        collider: collider,
      ),
    );
    context.reveal(
      entity,
      collider: collider,
      mechanism: pickup,
      size: entity.vector('size') ?? defaultSize,
    );
  }
}

final class NoteKind extends EntityKind {
  const NoteKind() : super(ShooterEntities.note);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireText(entity, scope, out, 'text');
  }
}
