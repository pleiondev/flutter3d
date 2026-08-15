/// A platformer: the second genre, and the instrument that tests the first.
///
/// SPEC stage 5 asks for "a game that is not a shooter, without a single edit
/// in `lib/src/`", and the value of it is not the game — it is what the attempt
/// finds. Three hardcoded object types had already been dug out of the engine
/// by imagining this one; sketching it for real found five more, all in input,
/// and they are fixed rather than worked around.
///
/// What this package needed from the engine and got unchanged: the fixed step,
/// the character controller, the level format and its validator, the entity
/// registry, mechanisms, movers, riders, exits, health, the ECS and the
/// snapshot. What it had to bring itself: its own jump policy, its own purse,
/// its own collectible, and its own step order.
///
/// Nothing here imports the renderer, so all of it runs in a test with no
/// device.
library;

export 'src/actions.dart';
export 'src/checkpoint.dart';
export 'src/collectible.dart';
export 'src/crate.dart';
export 'src/entity_kinds.dart';
export 'src/follow_camera.dart';
export 'src/hazard.dart';
export 'src/purse.dart';
export 'src/runner.dart';
export 'src/simulation.dart';
export 'src/spring.dart';
export 'src/surfaces.dart';
