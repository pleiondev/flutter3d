/// The names a level document uses.
///
/// The vocabulary of the *format*, which is not everything a level may contain:
/// a game adds its own types and names them itself. `torch`, `lamp` and
/// `window` were here until the day this package stopped being one game's — see
/// `sample.dart`, which owns those three and the kinds behind them.
///
/// Kept as constants next to the kinds that implement them so a document, a
/// validator and an editor all spell them the same way.
abstract final class EntityTypes {
  static const String playerSpawn = 'player_spawn';

  /// A key. The *pickup* that grants one is a shooter's — see
  /// `ShooterEntities` — but the word stays here, because [LevelScope]
  /// gathers keys to answer whether a locked door names one that exists,
  /// and locking a thing behind a token is not one genre's idea.
  static const String key = 'key';
  static const String door = 'door';
  static const String lift = 'lift';
  static const String platform = 'platform';
  static const String button = 'button';
  static const String trigger = 'trigger';
  static const String exit = 'exit';

  /// A point the room is reflected from — see `ReflectionProbeKind`. The
  /// format's word rather than a game's, because a reflection is a fact
  /// about a room and not about what happens in it.
  static const String reflectionProbe = 'reflection_probe';
}
