/// The scene two backends are asked to draw, so their pictures can be compared.
///
/// **A separate entry point, because it is a fixture and not the engine.** It
/// used to be exported from `flutter3d.dart`, which put a test scene — a
/// hard-coded camera, two spheres and a light — into the public API of a
/// rendering library, where a reader has no way to tell it from something they
/// are meant to use.
///
/// It stays inside this package rather than moving to a test folder for the
/// reason its own file gives: an application on one backend and a test on
/// another both have to reach it, and writing the scene twice makes every
/// difference in the two pictures as likely to be a difference in the two
/// transcriptions.
///
///     import 'package:flutter3d/parity_scene.dart';
library;

export 'src/engine/render/parity_grid.dart';
export 'src/engine/render/parity_scene.dart';
