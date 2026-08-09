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
/// The application is where this meets the renderer.
library;

export 'src/input/desktop_input.dart';
export 'src/input/game_action.dart';
export 'src/input/input_state.dart';
export 'src/loop/fixed_step.dart';
export 'src/loop/game_loop.dart';
export 'src/level/brush_geometry.dart';
export 'src/level/json_reader.dart';
export 'src/level/level.dart';
export 'src/level/level_collision.dart';
export 'src/level/level_validator.dart';
export 'src/loop/interpolated.dart';
export 'src/physics/character_controller.dart';
export 'src/physics/collider.dart';
export 'src/physics/collision_shape.dart';
export 'src/physics/collision_world.dart';
export 'src/physics/spatial_grid.dart';
