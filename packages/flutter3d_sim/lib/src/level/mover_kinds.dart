import 'package:flutter3d_physics/flutter3d_physics.dart';

import '../world/mover.dart';
import 'entity_kind.dart';

/// Kinds that move a kinematic body along a fixed offset: a door, a lift and a
/// platform. Grouped together because they share one mechanism —
/// [EntityKind.requireTravel], a kinematic collider and a `speed`/`wait` pair —
/// and differ only in which [Mover] they hand it to.
final class DoorKind extends EntityKind {
  /// The `door` kind: a sized block with a `travel`, opened on request and
  /// locked by an optional `key`.
  const DoorKind() : super(EntityTypes.door);

  @override
  void validate(EntityCheck check) {
    final entity = check.entity;
    final scope = check.scope;
    final out = check.out;
    requireKeyExists(entity, scope, out);
    requireTravel(entity, scope, out);
    requireSize(entity, scope, out);
  }

  @override
  void spawn(EntitySpawn spawn) {
    final entity = spawn.entity;
    final context = spawn.context;
    final travel = entity.vector('travel');
    if (travel == null) return;
    final collider = place(entity, context, kind: ColliderKind.kinematic);
    final door = context.mechanisms.add(
      Door(
        name: entity.name,
        collider: collider,
        travel: travel,
        speed: entity.number('speed') ?? Door.defaultSpeed,
        wait: entity.number('wait') ?? Door.defaultWait,
        key: entity.string('key'),
      ),
    );
    context.reveal(entity, collider: collider, mechanism: door);
  }
}

/// Travels to the far end when called and back, as a [Lift].
final class LiftKind extends EntityKind {
  /// The `lift` kind: a sized block with a `travel`.
  const LiftKind() : super(EntityTypes.lift);

  @override
  void validate(EntityCheck check) {
    final entity = check.entity;
    final scope = check.scope;
    final out = check.out;
    requireTravel(entity, scope, out);
    requireSize(entity, scope, out);
  }

  @override
  void spawn(EntitySpawn spawn) {
    final entity = spawn.entity;
    final context = spawn.context;
    final travel = entity.vector('travel');
    if (travel == null) return;
    final collider = place(entity, context, kind: ColliderKind.kinematic);
    final lift = context.mechanisms.add(
      Lift(
        name: entity.name,
        collider: collider,
        travel: travel,
        speed: entity.number('speed') ?? Lift.defaultSpeed,
        wait: entity.number('wait') ?? Lift.defaultWait,
      ),
    );
    context.reveal(entity, collider: collider, mechanism: lift);
  }
}

/// Moves on its own timetable rather than waiting to be called.
final class PlatformKind extends EntityKind {
  /// The `platform` kind: a sized block with a `travel`, started `phase`
  /// seconds into its cycle.
  const PlatformKind() : super(EntityTypes.platform);

  @override
  void validate(EntityCheck check) {
    final entity = check.entity;
    final scope = check.scope;
    final out = check.out;
    requireTravel(entity, scope, out);
    requireSize(entity, scope, out);
  }

  @override
  void spawn(EntitySpawn spawn) {
    final entity = spawn.entity;
    final context = spawn.context;
    final travel = entity.vector('travel');
    if (travel == null) return;
    final collider = place(entity, context, kind: ColliderKind.kinematic);
    final platform = context.mechanisms.add(
      MovingPlatform(
        name: entity.name,
        collider: collider,
        travel: travel,
        speed: entity.number('speed') ?? MovingPlatform.defaultSpeed,
        wait: entity.number('wait') ?? MovingPlatform.defaultWait,
      ),
    );
    // So a row of them does not move as one slab.
    platform.offsetBy(entity.number('phase') ?? 0.0);
    context.reveal(entity, collider: collider, mechanism: platform);
  }
}
