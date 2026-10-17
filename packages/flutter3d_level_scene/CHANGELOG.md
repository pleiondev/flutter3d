## 1.0.0-rc.1+1

- **Breaking: `RenderView` is `CameraView`.** `LevelScene` and
  `LevelSceneParts` changed with it. `package:flutter/rendering.dart`
  exports a `RenderView` too, the root of a render tree, so a file importing
  both had to hide one. `RenderViewSettings` is `CameraViewSettings` and
  `FrameView.ofRenderView` is `FrameView.ofCameraView`; `dart fix` renames
  them.

## 1.0.0-rc.1

- **Breaking: `LevelBatch` is a class** with the same `node`, `mesh`,
  `bounds` and `brush`, so a batch can later say more of what it draws.
- **A substance named by id is read from the catalogue.**
  `LevelScene(materials:)` takes a `MaterialCatalog`, and a level material
  naming what it is made of (`physicalMaterial`) takes from the substance's
  optical group what the document leaves unsaid: a metal is drawn metallic
  in its own reflectance, and the roughness is the middle of the range the
  catalogue gives. An author's `metallic`, `baseColor` or `roughness` wins.
  `LevelScene.substanceOf` finds the substance, and `materialFrom` takes it
  as `substance:`.
- **A level material's parameter values reach its material.**
  `materialFrom` writes `LevelMaterial.parameters` into
  `RenderMaterial.parameters` as the document gives them.
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
