import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'entity_kinds.dart';

/// A box the runner can shove about.
///
/// Almost nothing: `RigidBody` in `flutter3d_physics` does mass, gravity,
/// resting, stacking and sleeping, and `PlatformerSimulation` already takes a
/// `Dynamics`, steps it and calls `push` with the runner's velocity — that
/// wiring was written and then left unused because nobody had made a body for
/// it. This is the body.
///
/// The stage-1 limits are worth knowing before authoring with it: **a crate
/// does not rotate.** It will not tip, it will not roll, and a stack of them
/// stays square. That is a decision recorded in SPEC §4.3, not an oversight,
/// and it is why a crate is a crate here rather than a barrel.
final class Crate {
  Crate({
    required CollisionWorld world,
    required Vector3 at,
    Vector3? size,
    double mass = 30.0,
    Object? userData,
  }) : body = RigidBody(
          world: world,
          shape: CollisionBox((size ?? defaultSize) / 2.0),
          position: at,
          mass: mass,
          friction: 0.8,
          layer: CollisionLayers.world,
          userData: userData,
        );

  /// Big enough to climb on, light enough to move: a crate that is neither is
  /// scenery.
  static final Vector3 defaultSize = Vector3(1.2, 1.2, 1.2);

  final RigidBody body;

  Collider get collider => body.collider;

  Vector3 get position => body.position;
}

/// A crate in a level document.
///
/// Holds its [dynamics] mutably, the way `MonsterKind` holds a bestiary and for
/// the same reason: one registry has to validate a document before there is a
/// world to spawn it into, and two registries could disagree about what a
/// document may contain.
final class CrateKind extends EntityKind {
  CrateKind({this.dynamics}) : super(PlatformerEntities.crate);

  /// Where a crate goes once there is a world. Null while validating.
  Dynamics? dynamics;

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final mass = entity.number('mass');
    if (mass != null && mass <= 0.0) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'has a mass of $mass, and a crate with no mass is a wall',
          where: scope.describe(entity),
        ),
      );
    }
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final world = dynamics;
    if (world == null) return;
    final size = entity.vector('size') ?? Crate.defaultSize;
    final crate = Crate(
      world: context.world,
      // The document points at the floor, as it does for a spawn and a
      // checkpoint; a body is a box about its middle.
      at: entity.position + Vector3(0.0, size.y / 2.0, 0.0),
      size: size,
      mass: entity.number('mass') ?? 30.0,
    );
    crate.body.userData = crate;
    world.add(crate.body);
    context.reveal(entity, collider: crate.collider, size: size);
  }
}

extension on RigidBody {
  set userData(Object? value) => collider.userData = value;
}
