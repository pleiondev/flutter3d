/// A level document turned into a scene: brushes into meshes, the level's
/// materials into engine materials, its lights, probes, decals, mirrors and
/// camera screens into nodes.
///
/// **Plain Dart, between the level and the renderer.** The application's
/// `LevelLoader` hands [LevelScene.build] the textures it decoded and wraps
/// the answer in a `LoadedLevel`; the editor's light optimizer and its agent
/// server hand it nothing and draw the level flat on the software renderer.
/// Neither has to depend on the other to do it.
library;

export 'src/level_scene.dart';
