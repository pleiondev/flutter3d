/// The simulation: everything a game does between one fixed step and the next,
/// and nothing that draws it or reads a device.
///
/// **Plain Dart, and that is the whole of why this package exists.** It was
/// `flutter3d_game`'s inside — the loop, the entity store, the level format,
/// the saves and replays, the world logic, the actors, the navigation, the
/// maths — and none of it ever imported Flutter. The eight
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
/// **The renderer.** `flutter3d_app` is where a level meets something that
/// draws it, and `flutter3d_game` is where a game's actors do; nothing here
/// knows that anything does.
///
/// **The cameras.** `CameraRig`, `PhotoCamera` and `RigSettings` place a view,
/// which no step reads, so they live in `flutter3d_camera` beside the virtual
/// cameras that drive them. What stays here looks like the view and is not:
/// a lightmap is a level asset baked from the level's geometry, a sequence
/// player steps in the simulation and directs its actors, and a light's
/// flicker is level data the step reads.
library;

// **Only this package's own API.** The physics, the plugin API and the
// foundation under it were re-exported here until 1.0.0-rc.1, so a game
// that named `CollisionWorld` or `Portable` through this import used a
// package its pubspec never named. A game imports each of them itself, or
// takes `flutter3d_game`, the one facade, which names what a first game
// needs.

export 'src/actors/actor.dart';
export 'src/actors/actor_components.dart';
export 'src/actors/actor_hurt.dart';
export 'src/actors/actor_strides.dart';
export 'src/actors/actor_system.dart';
export 'src/actors/behaviour_brain.dart';
export 'src/actors/behaviour_rule.dart';
export 'src/actors/behaviour_tree.dart';
export 'src/actors/brain.dart';
export 'src/actors/damageable.dart';
export 'src/actors/health.dart';
export 'src/cinema/sequence.dart';
export 'src/cinema/sequence_player.dart';
export 'src/ecs/ecs_world.dart';
export 'src/ecs/entity_remap.dart';
export 'src/ecs/snapshots.dart';
export 'src/input/action_set.dart';
export 'src/input/game_action.dart';
export 'src/input/input_state.dart';
export 'src/input/input_tape.dart';
export 'src/input/tunables.dart';
export 'src/level/breaches.dart';
export 'src/level/brush_geometry.dart';
export 'src/level/cutscene_kind.dart';
export 'src/level/data_source.dart';
export 'src/level/entity_kind.dart';
export 'src/level/entity_kinds.dart';
export 'src/level/heightfield.dart';
export 'src/level/heightfield_geometry.dart';
export 'src/level/heightfield_tiles.dart';
export 'src/level/json_reader.dart';
export 'src/level/level.dart';
export 'src/level/level_collision.dart';
export 'src/level/level_diff.dart';
export 'src/level/level_issue.dart';
export 'src/level/level_patch.dart';
export 'src/level/level_validator.dart';
export 'src/level/level_visibility.dart';
export 'src/level/lightmap.dart';
export 'src/level/lightmap_baker.dart';
export 'src/level/lightmap_layout.dart';
export 'src/level/spawn_context.dart';
export 'src/level/surface_kinds.dart';
export 'src/level/surface_table.dart';
export 'src/loop/determinism_check.dart';
export 'src/loop/difficulty.dart';
export 'src/loop/engine_loop.dart';
export 'src/loop/engine_time.dart';
export 'src/loop/frame_cadence.dart';
export 'src/loop/game_event.dart';
export 'src/loop/genre_plugin.dart';
export 'src/loop/headless_run.dart';
export 'src/loop/interpolated.dart';
export 'src/loop/isolate_simulation.dart';
export 'src/loop/local_simulation.dart';
export 'src/loop/loop_change.dart';
export 'src/loop/pace.dart';
export 'src/loop/pause_gate.dart';
export 'src/loop/published_worlds.dart';
export 'src/loop/run_loop.dart';
export 'src/loop/run_outcome.dart';
export 'src/loop/sim_queries.dart';
export 'src/loop/simulation_handle.dart';
export 'src/loop/step_systems.dart';
export 'src/math/motion.dart';
export 'src/math/spline.dart';
export 'src/math/tolerances.dart';
export 'src/nav/automap.dart';
export 'src/nav/avoidance.dart';
export 'src/nav/flow_field.dart';
export 'src/nav/jump_links.dart';
export 'src/nav/nav_grid.dart';
export 'src/nav/navigation.dart';
export 'src/nav/navmesh/mesh_links.dart' show NavMeshLink;
export 'src/nav/navmesh/navmesh.dart';
export 'src/nav/navmesh/navmesh_config.dart';
export 'src/nav/navmesh/route.dart' show NavMeshRoute;
export 'src/nav/navmesh/span_field.dart' show NavLattice;
export 'src/physics/layers.dart';
export 'src/procgen/erosion.dart';
export 'src/procgen/exit_reachable.dart';
export 'src/procgen/generate_async.dart';
export 'src/procgen/generate_level.dart';
export 'src/procgen/wfc.dart';
export 'src/save/data_source_trace.dart';
export 'src/save/demo.dart';
export 'src/save/entity_tracks.dart';
export 'src/save/event_trace.dart';
export 'src/save/first_differing_path.dart';
export 'src/save/game_random.dart';
export 'src/save/replay.dart';
export 'src/save/rewind.dart';
export 'src/save/run_stats.dart';
export 'src/save/save_record.dart';
export 'src/save/save_schema.dart';
export 'src/save/scoring.dart';
export 'src/save/simulation_version.dart';
export 'src/save/snapshot.dart';
export 'src/save/state_digest.dart';
export 'src/save/step_time_trace.dart';
export 'src/save/tally.dart';
export 'src/save/tape_bisect.dart';
export 'src/share/run_service.dart';
export 'src/share/share_bundle.dart';
export 'src/sim_formats.dart';
export 'src/telemetry/heatmap.dart';
export 'src/telemetry/resimulation.dart';
export 'src/telemetry/telemetry_consent.dart';
export 'src/telemetry/telemetry_upload.dart';
export 'src/world/cutscene.dart';
export 'src/world/exit.dart';
export 'src/world/key_ring.dart';
export 'src/world/light_fixture.dart';
export 'src/world/mechanism.dart';
export 'src/world/mover.dart';
export 'src/world/powers.dart';
export 'src/world/rider.dart';
export 'src/world/signals.dart';
export 'src/world/takeable.dart';
export 'src/world/world_step.dart';
