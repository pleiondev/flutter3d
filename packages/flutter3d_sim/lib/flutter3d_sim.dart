/// The simulation: everything a game does between one fixed step and the next,
/// and nothing that draws it or reads a device.
///
/// **Plain Dart, and that is the whole of why this package exists.** It was
/// `flutter3d_game`'s inside — the loop, the entity store, the level format,
/// the saves and replays, the world logic, the actors, the navigation, the
/// camera rig, the maths — and none of it ever imported Flutter. The eight
/// files that did are widgets, a `MediaQuery` read and one `debugPrint`, and
/// they stayed behind with the devices they belong to.
///
/// ## What it buys
///
/// A server that verifies a submitted run has to replay it through **the same
/// simulation the player ran**. Not an equivalent implementation and not a
/// rules check: the moment a second copy of the game logic exists on the
/// server, the verification stops proving anything about the first. That
/// server is an ordinary Dart process in a container, and requiring a Flutter
/// SDK there to advance a headless step is a blocker rather than an
/// inconvenience.
///
/// It buys two more things that are not the reason and are worth having: a
/// simulation that runs under `dart test` with no binding at all, and a
/// boundary that a scan can enforce — `tool/structure.dart` reads this
/// package's source and fails if anything in it names Flutter.
///
/// ## What is deliberately not here
///
/// **Devices.** A touch stick, a keyboard, a gamepad route and the widget that
/// hosts them are `flutter3d_game`'s, because they are Flutter. What crosses
/// the boundary is [InputState] — intent, with the device forgotten — and
/// [InputTape], which is that intent written down per step and is therefore
/// also the format a run is submitted to a server in.
///
/// **The renderer.** As before: `flutter3d_bridge` is where a simulation meets
/// something that draws it, and nothing here knows that anything does.
library;

// Collision, queries and the character controller. Re-exported so that a game
// depending on this one still gets a working world from a single import, which
// is what `flutter3d_game` did for it before the split.
export 'package:flutter3d_physics/flutter3d_physics.dart';

export 'src/actors/actor.dart';
export 'src/actors/actor_components.dart';
export 'src/actors/actor_hurt.dart';
export 'src/actors/actor_system.dart';
export 'src/actors/brain.dart';
export 'src/actors/damageable.dart';
export 'src/actors/health.dart';
export 'src/camera/camera_rig.dart';
export 'src/camera/rig_tuning.dart';
export 'src/ecs/ecs_world.dart';
export 'src/ecs/entity.dart';
export 'src/input/game_action.dart';
export 'src/input/input_state.dart';
export 'src/input/input_tape.dart';
export 'src/level/breaches.dart';
export 'src/level/brush_geometry.dart';
export 'src/level/entity_kind.dart';
export 'src/level/json_reader.dart';
export 'src/level/level.dart';
export 'src/level/level_collision.dart';
export 'src/level/level_issue.dart';
export 'src/level/level_validator.dart';
export 'src/level/level_visibility.dart';
export 'src/level/lightmap.dart';
export 'src/level/lightmap_baker.dart';
export 'src/level/lightmap_layout.dart';
export 'src/level/spawn_context.dart';
export 'src/level/surface_table.dart';
export 'src/loop/fixed_step.dart';
export 'src/loop/game_event.dart';
export 'src/loop/game_loop.dart';
export 'src/loop/interpolated.dart';
export 'src/loop/pace.dart';
export 'src/loop/pause_gate.dart';
export 'src/loop/run_outcome.dart';
export 'src/loop/step_systems.dart';
export 'src/math/motion.dart';
export 'src/math/spline.dart';
export 'src/math/tolerances.dart';
export 'src/nav/automap.dart';
export 'src/nav/flow_field.dart';
export 'src/nav/jump_links.dart';
export 'src/nav/nav_grid.dart';
export 'src/nav/navigation.dart';
export 'src/physics/layers.dart';
export 'src/save/demo.dart';
export 'src/save/game_random.dart';
export 'src/save/replay.dart';
export 'src/save/rewind.dart';
export 'src/save/snapshot.dart';
export 'src/save/state_digest.dart';
export 'src/save/tally.dart';
export 'src/world/exit.dart';
export 'src/world/key_ring.dart';
export 'src/world/light_fixture.dart';
export 'src/world/mechanism.dart';
export 'src/world/mover.dart';
export 'src/world/rider.dart';
export 'src/world/signals.dart';
export 'src/world/takeable.dart';
export 'src/world/world_step.dart';
