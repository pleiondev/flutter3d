/// The binding between the renderer and the simulation.
///
/// `flutter3d_game` depends on `flutter`, `mouse_capture` and `vector_math` and
/// on nothing else — not on `flutter3d`, not on `flutter_gpu` — which is what
/// makes its simulation headless and testable without a device. `flutter3d`, in
/// return, must never learn what a monster is. Neither rule leaves anywhere for
/// the mapping between them to live, and this package is that place: level
/// geometry to mesh nodes, an actor to its visual, a weapon to a view model, a
/// glowing fixture to the light it drives.
///
/// Everything here is mechanism. What a torch looks like, what colour a runner
/// is and how a shotgun is shaped are decided by the game and handed in —
/// see [FixtureAppearance], [MonsterAppearance] and [WeaponView]'s models.
///
/// A caveat worth stating rather than papering over: extracting this package
/// does not make the stack content-free. `flutter3d_game` itself ships a monster
/// roster, a weapon roster and a list of entity types, and this package
/// references them. That is a separate problem.
library;

export 'src/fixture_visuals.dart';
export 'src/level_loader.dart';
export 'src/monster_visuals.dart';
export 'src/shared_meshes.dart';
export 'src/weapon_view.dart';
