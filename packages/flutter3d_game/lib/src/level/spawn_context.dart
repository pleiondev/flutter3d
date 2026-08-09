import '../actors/monster.dart';
import '../actors/monster_system.dart';
import '../physics/collision_world.dart';

/// What an entity is given when it is asked to become real.
///
/// Grows a field per system as the game does — pickups, doors and triggers will
/// each add one. A context rather than a long parameter list because every
/// [EntityKind.spawn] takes the same set and most kinds use one of it.
final class SpawnContext {
  SpawnContext({
    required this.world,
    required this.monsters,
    this.onMonsterSpawned,
  });

  final CollisionWorld world;
  final MonsterSystem monsters;

  /// Told about each monster as it appears.
  ///
  /// The hook exists because the simulation has no idea what anything looks
  /// like, and the application does: this is where a body gets a mesh. Keeping
  /// it a callback rather than having the spawner build one is what stops the
  /// game engine from needing the renderer.
  final void Function(Monster monster)? onMonsterSpawned;
}
