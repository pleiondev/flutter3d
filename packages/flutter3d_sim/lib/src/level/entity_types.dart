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
  /// Where the player starts — see `PlayerSpawnKind`; a level needs one.
  static const String playerSpawn = 'player_spawn';

  /// A key. The *pickup* that grants one is a shooter's — see
  /// `ShooterEntities` — but the word stays here, because [LevelScope]
  /// gathers keys to answer whether a locked door names one that exists,
  /// and locking a thing behind a token is not one genre's idea.
  static const String key = 'key';

  /// A block that opens when asked and closes itself — a `Door`.
  static const String door = 'door';

  /// A block that travels to the far end when called and back — a `Lift`.
  static const String lift = 'lift';

  /// A block that goes back and forth for ever — a `MovingPlatform`.
  static const String platform = 'platform';

  /// A panel that fires its target on use — a `Button`.
  static const String button = 'button';

  /// A volume that fires its target when walked into — a `TriggerVolume`.
  static const String trigger = 'trigger';

  /// The way out of the level — an `Exit`.
  static const String exit = 'exit';

  /// A point the room is reflected from — see `ReflectionProbeKind`. The
  /// format's word rather than a game's, because a reflection is a fact
  /// about a room and not about what happens in it.
  static const String reflectionProbe = 'reflection_probe';

  /// A cutscene a trigger starts — see `CutsceneKind`. The format's word,
  /// because a level telling its own story is not one genre's idea.
  static const String cutscene = 'cutscene';

  /// An instance of one of the level's prefabs — see `PrefabInstance`. The
  /// format's word, and one no game spawns: [expandPrefabs] replaces every
  /// instance with the entities it stands for before anything reads them.
  static const String prefab = 'prefab';

  /// A picture projected onto what stands in a box — see `DecalKind`.
  static const String decal = 'decal';

  /// A floor or a pool that mirrors the room — see `ReflectorKind`.
  static const String reflector = 'reflector';

  /// A camera whose picture a material shows — see `CameraScreenKind`.
  static const String cameraScreen = 'camera_screen';
}
