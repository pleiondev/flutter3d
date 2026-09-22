/// The scene two backends are asked to draw, so their pictures can be compared.
///
/// **A separate entry point, because it is a fixture and not the engine.**
/// See `flutter3d`'s own `parity_scene.dart` — the barrel this package's
/// consumers reached before mcp-03n moved the rendering core here — for why
/// this stays out of the main barrel.
///
///     import 'package:flutter3d_core/parity_scene.dart';
library;

export 'src/engine/render/parity_grid.dart';
export 'src/engine/render/parity_scene.dart';
