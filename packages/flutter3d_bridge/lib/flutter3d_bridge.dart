/// The binding between the renderer and the simulation.
///
/// `flutter3d_game` depends on `flutter`, `mouse_capture` and `vector_math` and
/// on nothing else — not on `flutter3d`, not on `flutter_gpu` — which is what
/// makes its simulation headless and testable without a device. `flutter3d`, in
/// return, must never learn what a monster is. Neither rule leaves anywhere for
/// the mapping between them to live, and this package is that place: level
/// geometry to mesh nodes, an actor to its visual, a glowing fixture to the
/// light it drives.
///
/// Everything here is mechanism. What a torch looks like and what colour a
/// runner is are decided by the game and handed in — see [FixtureAppearance]
/// and [ActorAppearance].
///
/// The caveat this doc used to end on — that extracting the package did not
/// make the stack content-free, because the game layer still shipped a monster
/// roster and a weapon roster and this package referenced them — has been
/// answered. Those live in `flutter3d_shooter` now, and the view model of a
/// weapon held in the hands went with them: it was the one thing in here that
/// only a shooter could want.
library;

export 'src/actor_visuals.dart';
export 'src/fixture_visuals.dart';
export 'src/level_loader.dart';
export 'src/shared_meshes.dart';
