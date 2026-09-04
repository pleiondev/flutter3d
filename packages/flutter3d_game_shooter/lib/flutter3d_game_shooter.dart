/// The parts of a first-person shooter that are not parts of an engine.
///
/// `flutter3d_game` knows what a body, a brain, a mechanism and a step are.
/// What a monster is, what a shotgun does, what a medkit gives and what order a
/// shooter's step runs in are here — and a platformer or a racing game gets
/// none of it, which is the whole reason the package exists.
///
/// The line between the two is the one the game layer's own README already
/// drew: **machinery stays, vocabulary moves.** `Mechanism`, `Actor`,
/// `MechanismEvents.taken` and the level format are machinery. [Inventory],
/// [Gift], [Arsenal] and [GameSimulation] answer the machinery with content,
/// and content belongs to a genre.
///
/// Nothing here imports the renderer. [WeaponView] does, and it is in
/// `bridge.dart` for that reason; a test holds the split.
library;

export 'src/actions.dart';
export 'src/collector.dart';
export 'src/combat/blast.dart';
export 'src/combat/hit_zones.dart';
export 'src/combat/hitscan.dart';
export 'src/combat/projectile.dart';
export 'src/combat/projectile_types.dart';
export 'src/combat/shot_hit.dart';
export 'src/combat/weapon.dart';
export 'src/combat/weapon_behaviour.dart';
export 'src/combat/weapon_def.dart';
export 'src/entity_kinds.dart';
export 'src/events.dart';
export 'src/gift.dart';
export 'src/inventory.dart';
export 'src/monsters.dart';
export 'src/pickup.dart';
export 'src/player.dart';
export 'src/secret.dart';
export 'src/simulation.dart';
export 'src/step_phases.dart';
