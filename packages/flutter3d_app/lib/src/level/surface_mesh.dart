/// The twenty lines where the simulation's triangles become the engine's.
///
/// `meshDataOf` moved to `flutter3d_editor_core`'s `level_scene.dart` with
/// the rest of the Flutter-free half of loading a level, so a program started
/// by `dart run` builds brushes into the same vertices a game does. Exported
/// from here still, because terrain and the strategy bridge reach it through
/// this package and have no reason to learn where it went.
library;

export 'package:flutter3d_editor_core/flutter3d_editor_core.dart'
    show meshDataOf;
