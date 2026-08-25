import 'entity_kind.dart';

/// The kinds a build knows about, by name.
///
/// A registry rather than a hardcoded list inside the validator, so a game
/// built on this package can add its own without editing it — and so tests can
/// validate against a deliberately small set.
final class EntityRegistry {
  EntityRegistry(Iterable<EntityKind> kinds)
      : _byType = <String, EntityKind>{
          for (final kind in kinds) kind.type: kind,
        };

  /// Everything this game ships with.
  /// **There is no ready-made registry, and that is deliberate.**
  ///
  /// There was one, and it listed fourteen kinds: a spawn point, three movers,
  /// a button, a trigger, a note, an exit, a monster, a pickup, a key, and
  /// three kinds of lamp. A second game loading a level got every one of them.
  ///
  /// The first attempt at fixing that replaced it with a factory taking a
  /// monster catalog and a gift registry — which still says every game has
  /// monsters and pickups. They do not. A racing game has neither; a puzzle
  /// game has neither; a walking simulator has neither and no exit either.
  ///
  /// So this package offers *kinds*, and a game composes its own vocabulary
  /// out of the ones it wants:
  ///
  /// ```dart
  /// final kinds = EntityRegistry(<EntityKind>[
  ///   const PlayerSpawnKind(),
  ///   const DoorKind(),
  ///   MonsterKind(myMonsters),      // only if this game has monsters
  ///   MyOwnKind(),                  // and whatever it invents
  /// ]);
  /// ```
  ///
  /// `sample.dart` assembles the shooter's set, which is one call and is an
  /// example rather than a default.

  final Map<String, EntityKind> _byType;

  EntityKind? operator [](String type) => _byType[type];

  Iterable<String> get types => _byType.keys;

  bool knows(String type) => _byType.containsKey(type);
}
