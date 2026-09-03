## 0.4.2

* **`ActorVisuals.layerMask`.** The layers every actor's mesh is drawn on,
  capsule and model alike, set on each mesh node because a render list asks
  the node it draws and not its parents. The default layer alone unless a
  game says otherwise — and the reason one would is `RenderSettings.xray`,
  which names a layer to draw silhouettes for.

## 0.4.1

* **A level's sidecars are read beside it.** `LevelLoader` looks for
  `<level>.visibility.json` and `<level>.lightmap.bin` next to the document,
  refuses either with a word when its hash no longer matches the level, and
  otherwise hands the batches to a `VisibilityCuller` and every brush vertex
  its place in the lightmap, uploaded as one texture the material samples.
* `SoundOcclusion`: the walls between a sound and the ear, each taking half,
  as a gain and a muffle for `AudioScene.occlusion`.
* `LevelLoader.rebuildBrushes` draws the walls again after a breach and
  invalidates the static shadows; `LoadedLevel` keeps its brush nodes, its
  culler and its lightmap so it can.
* Texture uploads that are refused say why, in the level's issues.

## 0.4.0

* **A level change releases what the level built.** Both visuals classes kept
  their models on a comment naming a shared cache that has never existed; they
  now release them through the future, so a model that finishes reading after
  its level ended is released the moment it arrives. `LoadedLevel` remembers
  the brush meshes the loader uploaded and gained `dispose` to give them and
  the material maps back — `RunSession.close` is the moment both are written
  for. `FixtureVisuals` got the generation guard its sibling already had, so
  a late model no longer instantiates into a torn-down scene.

## 0.3.0

* **A light fixture no longer casts a shadow into its own light.** Every torch
  in the crypt was drawing a black pyramid down the wall beneath it and a dark
  apron across the floor: a torch's light sits a third of a metre out from the
  wall, its bracket hangs in the same space, and a blocker that close to a point
  light shadows everything the light reaches. Opt back in per fixture with
  `castsShadow: true` on the entity, for a shade whose pattern is the point.
* `ActorVisuals` decides an animation's wrap and a model's yaw, so a death
  animation stops looping and a monster faces the way it moves.

## 0.2.0

* View models for a weapon held in the hands, and particle effects driven by
  what the simulation reported rather than by what it looks like.
* An actor is placed by its feet, which is how the level document means it.

## 0.1.0

* The binding between the two halves: level geometry to mesh nodes, actors to
  visuals, fixtures to the lights they drive.
* The one package allowed to know both `flutter3d` and `flutter3d_game`.
