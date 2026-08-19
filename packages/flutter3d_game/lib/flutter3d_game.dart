/// The game layer: a simulation that runs at a fixed rate, and input that has
/// forgotten which device it came from.
///
/// Everything here is free of `flutter_gpu` and of `flutter3d`, and most of it
/// is free of Flutter altogether. That is the same rule the engine's geometry
/// and scene layers already follow, applied to the part of a game that breaks
/// most quietly: a collision that lets the player through a wall once in a
/// thousand steps, a jump that is a different height on a faster monitor, a
/// press swallowed at a low frame rate. None of those are visible in a
/// screenshot, and all of them are reachable from a plain unit test.
///
/// `flutter3d_bridge` is where this meets the renderer.
library;

// Collision and character movement are their own package now — plain Dart, no
// Flutter, no renderer. Re-exported so that a game depending on this one still
// gets a working world from a single import, which is what it was doing before
// the split.
export 'package:flutter3d_physics/flutter3d_physics.dart';

export 'src/actors/actor.dart';
export 'src/actors/actor_components.dart';
export 'src/actors/actor_system.dart';
export 'src/actors/brain.dart';
export 'src/actors/damageable.dart';
export 'src/actors/health.dart';
export 'src/camera/camera_rig.dart';
export 'src/camera/rig_tuning.dart';
export 'src/config/accommodations.dart';
export 'src/config/game_config.dart';
export 'src/ecs/ecs_world.dart';
export 'src/ecs/entity.dart';
export 'src/input/bindings.dart';
export 'src/input/desktop_input.dart';
export 'src/input/game_action.dart';
export 'src/input/input_state.dart';
export 'src/input/pad_input.dart';
export 'src/input/playing.dart';
export 'src/input/touch_controls.dart';
export 'src/level/brush_geometry.dart';
export 'src/level/entity_kind.dart';
export 'src/level/json_reader.dart';
export 'src/level/level.dart';
export 'src/level/level_collision.dart';
export 'src/level/level_issue.dart';
export 'src/level/level_validator.dart';
export 'src/level/spawn_context.dart';
export 'src/loop/fixed_step.dart';
export 'src/loop/game_loop.dart';
export 'src/loop/interpolated.dart';
export 'src/loop/pace.dart';
export 'src/loop/pause_gate.dart';
export 'src/loop/run_outcome.dart';
export 'src/math/spline.dart';
export 'src/nav/flow_field.dart';
export 'src/nav/nav_grid.dart';
export 'src/nav/navigation.dart';
export 'src/physics/layers.dart';
export 'src/save/game_random.dart';
export 'src/save/snapshot.dart';
export 'src/world/exit.dart';
export 'src/world/key_ring.dart';
export 'src/world/light_fixture.dart';
export 'src/world/mechanism.dart';
export 'src/world/mover.dart';
export 'src/world/rider.dart';
export 'src/world/signals.dart';
export 'src/world/takeable.dart';
export 'src/world/world_step.dart';
