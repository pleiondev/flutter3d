import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import '../physics/layers.dart';
import '../world/exit.dart';
import '../world/signals.dart';
import 'entity_def.dart';
import 'entity_kind.dart';
import 'level_issue.dart';
import 'spawn_context.dart';

/// Kinds built on a trigger collider: a button, a trigger volume and an exit.
/// Grouped because all three place a [ColliderKind.trigger] and drive a
/// [Signal] or [Exit] from it, rather than a kinematic body.
final class ButtonKind extends EntityKind {
  const ButtonKind() : super(EntityTypes.button);

  /// A panel, not a block: a button is something on a wall.
  static Vector3 get defaultSize => Vector3(0.6, 0.6, 0.15);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireTarget(entity, scope, out);
    requireKeyExists(entity, scope, out);
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final target = entity.string('target');
    if (target == null) return;
    final collider = place(
      entity,
      context,
      kind: ColliderKind.trigger,
      layer: CollisionLayers.trigger,
      mask: CollisionLayers.player,
      fallbackSize: defaultSize,
    );
    final button = context.mechanisms.add(
      Button(
        name: entity.name,
        target: target,
        collider: collider,
        once: entity.flag('once'),
        key: entity.string('key'),
      ),
    );
    context.reveal(
      entity,
      collider: collider,
      mechanism: button,
      size: entity.vector('size') ?? defaultSize,
    );
  }
}

final class TriggerKind extends EntityKind {
  const TriggerKind() : super(EntityTypes.trigger);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireTarget(entity, scope, out);
    requireSize(entity, scope, out);
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final target = entity.string('target');
    if (target == null) return;
    // Monsters can be allowed to set a trigger off, which is how an ambush
    // works, but the default is the player alone — otherwise the first monster
    // to wander through the room springs every trap in it.
    final who = entity.flag('anyone')
        ? CollisionLayers.player | CollisionLayers.actor
        : CollisionLayers.player;
    final collider = place(
      entity,
      context,
      kind: ColliderKind.trigger,
      layer: CollisionLayers.trigger,
      mask: who,
    );
    // Invisible by design, so no fixture is reported.
    context.mechanisms.add(
      TriggerVolume(
        name: entity.name,
        target: target,
        collider: collider,
        once: entity.flag('once', orElse: true),
      ),
    );
  }
}

final class ExitKind extends EntityKind {
  const ExitKind() : super(EntityTypes.exit);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireKeyExists(entity, scope, out);
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    // The player alone, and not because monsters would mind: a monster
    // wandering across the finish line would end the level from the far side
    // of the map with nobody watching.
    final collider = place(
      entity,
      context,
      kind: ColliderKind.trigger,
      layer: CollisionLayers.trigger,
      mask: CollisionLayers.player,
      fallbackSize: Vector3(1.5, 2.5, 1.5),
    );
    final exit = context.mechanisms.add(
      Exit(
        name: entity.name,
        collider: collider,
        next: entity.string('next'),
        message: entity.string('text'),
        key: entity.string('key'),
      ),
    );
    // **Revealed, like every other piece of furniture in a level.** It was the
    // one kind that spawned no fixture at all, so the goal of a two hundred and
    // sixty metre level was marked by nothing: a player found it by walking
    // into an invisible volume, and the only clue was whatever coins the author
    // happened to scatter nearby. What it looks like is still the game's
    // business — this only says there is something there to look at.
    context.reveal(
      entity,
      collider: collider,
      mechanism: exit,
      size: entity.vector('size') ?? Vector3(1.5, 2.5, 1.5),
    );
  }
}
