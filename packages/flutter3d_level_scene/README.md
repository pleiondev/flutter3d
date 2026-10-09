# flutter3d_level_scene

A [flutter3d](https://flutter3d.pleion.dev) level document turned into a
scene, in plain Dart.

- **`LevelScene.build`**: the level's brushes as uploaded meshes, batched per
  material (`LevelBatching.perMaterial`, what a game draws with) or per brush
  (`LevelBatching.perBrush`, so a pixel names the brush it belongs to); its
  lights, reflection probes, decals, mirrors and camera screens as nodes.
  The answer is a `LevelSceneParts`: the scene, and the parts of it a caller
  keeps to rebuild, cull or release.
- **`LevelScene.materialFrom`**: a level material as an engine material, the
  one place that knows both.
- **`meshDataOf`**: a `BrushSurface` interleaved into the engine's standard
  vertex layout, for the brushes and for terrain.

Nothing here reads a file. The textures a level names and the `.fmat`
materials it defers to are loaded by the caller and handed in already on the
device; a caller with neither hands nothing, and every surface is drawn in
the numbers the document carries.

```dart
import 'package:flutter3d_level_scene/flutter3d_level_scene.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

final parts = const LevelScene().build(
  Level.fromJson(document),
  device: device,
);
final scene = parts.scene; // the brushes, lights and probes, ready to draw
```

`flutter3d_app`'s `LevelLoader` is built on this, with the asset bundle and
the image decoder in front of it; the level editor's light optimizer and its
agent server use it with no window at all. Until 1.0.0-rc.1 it was part of
`flutter3d_editor_core`.
