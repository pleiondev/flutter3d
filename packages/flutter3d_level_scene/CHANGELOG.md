## 1.0.0-rc.1

- **The first release: a level turned into a scene, in a package of its
  own.** `LevelScene`, `LevelSceneParts`, `LevelBatch`, `LevelBatching` and
  `meshDataOf` come from `flutter3d_editor_core`. The application's level
  loader used to depend on the editor's document layer to reach them; now
  the application and the editor both stand on this, and a game resolves no
  editor to load a level. `dart fix` moves the imports.
