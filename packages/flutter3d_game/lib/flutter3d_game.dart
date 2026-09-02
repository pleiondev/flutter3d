/// The game layer: a simulation that runs at a fixed rate, and input that has
/// forgotten which device it came from.
///
/// **What is left here is the Flutter half**, and it is small: a touch stick, a
/// touch button, the widget that lays them out, the keyboard and mouse, the
/// accessibility settings that read a `MediaQuery`, and the diagnostics sink.
/// Everything a step actually does moved to `flutter3d_sim`, which is plain
/// Dart and can therefore run on a server — see that package for why that
/// matters more than tidiness. It is re-exported below, so a game that imported
/// this one keeps working unchanged.
///
/// Everything here is free of `flutter_gpu` and of `flutter3d`. That is the same rule the engine's geometry
/// and scene layers already follow, applied to the part of a game that breaks
/// most quietly: a collision that lets the player through a wall once in a
/// thousand steps, a jump that is a different height on a faster monitor, a
/// press swallowed at a low frame rate. None of those are visible in a
/// screenshot, and all of them are reachable from a plain unit test.
///
/// `flutter3d_bridge` is where this meets the renderer.
library;

// The simulation, and through it `flutter3d_physics`. Re-exported rather than
// left for the caller to add, so that the split costs no existing program a
// line: `import 'package:flutter3d_game/flutter3d_game.dart'` still hands over
// the loop, the level, the saves and the collision world.
export 'package:flutter3d_sim/flutter3d_sim.dart';
export 'src/config/accommodations.dart';
export 'src/config/game_config.dart';
export 'src/diagnostics/issues.dart';
export 'src/input/bindings.dart';
export 'src/input/desktop_input.dart';
export 'src/input/pad_actions.dart';
export 'src/input/playing.dart';
export 'src/input/touch_controls.dart';
