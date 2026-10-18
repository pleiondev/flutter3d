import 'entity_kind.dart';

/// Where the player starts: a coordinate and a facing a game reads, which
/// spawns nothing and checks nothing of its own.
final class PlayerSpawnKind extends EntityKind {
  /// The `player_spawn` kind.
  const PlayerSpawnKind() : super(EntityTypes.playerSpawn);
}
