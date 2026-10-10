## 1.0.0-rc.1

- **A level light's strength reaches its node as it is.** A level's lights
  are candela and lux since level format 5, so `LevelScene.lightOf` no
  longer multiplies by the pre-1.0 unit, and a kind of level light it has no
  node for is refused with an `ArgumentError`.

- **The first release: a level turned into a scene, in a package of its
  own.** `LevelScene`, `LevelSceneParts`, `LevelBatch`, `LevelBatching` and
  `meshDataOf` come from `flutter3d_editor_core`. The application's level
  loader used to depend on the editor's document layer to reach them; now
  the application and the editor both stand on this, and a game resolves no
  editor to load a level. `dart fix` moves the imports.
