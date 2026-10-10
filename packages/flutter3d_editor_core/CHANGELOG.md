## 1.0.0-rc.1

- **`EditorPieces.addComponent` refuses one of the editor's own kinds**
  with an `ArgumentError`, so an entity can no longer gain a second copy of
  a built-in component.
- **A project made from the scaffold templates depends on
  `flutter3d_plugin_api`**, which its seed genre is written against, so it
  compiles as generated.

- **Breaking: `AddLight` is `AddLevelLight`, `MoveBy` is
  `MoveSelectionBy`, `Listed` is `ListedPiece`, and `contentsOf` is
  `piecesOf`.** The modeller's commands and listing in
  `flutter3d_model_core` had the same names; a public name has one home
  across the published packages now. The journal names (`addLight`,
  `moveBy`) are unchanged, so a journal written before reads the same.
- **Breaking: `OpenKind` is `flutter3d_sim`'s.** It was declared here and,
  identically, in `flutter3d_game`; both use the one beside `EntityKind`
  now. `vocabularyOf` is unchanged.
- **Breaking: `LevelScene`, `LevelSceneParts`, `LevelBatch`,
  `LevelBatching` and `meshDataOf` are `flutter3d_level_scene`'s.** Building
  a scene from a level is what the application's loader and the editor's
  light optimizer both stand on, and the application should not depend on
  the editor to reach it. `dart fix` moves the imports.

- **`EditorRegistry` is declared here**, the slot `EditorPieces` fills; it
  was a marker in `flutter3d_plugin_api`.

- **Breaking: `GeneratorRefused` is `GeneratorException`** (decision H), with
  the same members; `dart fix` renames it.

- **A scaffolded project starts from `Flutter3dView`.** Its `lib/main.dart`
  is `flutter3d_game`'s example: one view that opens the device and runs
  the loop, with a small genre of the seed's own walking a body through the
  level on an `ActionMap` and the event bus. The project no longer gets
  `lib/src/backend.dart` or a `flutter_bloc` dependency, and its README
  points at nothing inside the flutter3d repository.
- **Breaking: one suffix for settings, Settings, and Descriptor in the
  HAL.** `SamplerOptions` is `SamplerDescriptor`. Every settings class is
  `final` with a `const` constructor and a `copyWith` over every field; a
  nullable field is reset with `copyWith(clearX: true)`. `dart fix` carries
  the renames.
- **Breaking: public constants are lowerCamelCase, without the k prefix,
  as Effective Dart asks.** `kGizmoSize` is `gizmoSize`, `kLight` is
  `paletteLight`, `kLooksFile` is `looksFile`. The values are the same;
  `dart fix` carries the renames.
- **Breaking: a boolean reads as a question, and no `bool` is positional.**
  `Editing.mayOverwrite` is `canOverwrite`; `LightPlan.changes` is
  `hasChanges`. `dart fix` carries the renames.
- **Breaking: a field of view is `fovY`**, in radians, wherever this package
  names one (docs/CONTRACTS.md).
- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `BehaviourKinds` is `BehaviorKinds`, `behaviourKinds` is
  `behaviorKinds`, `centre` is `center`, `colour` is `color`,
  `removeBehaviour` is `removeBehavior`, `setBehaviour` is `setBehavior`.
  Only the Dart names changed: a file keeps the keys it was written with,
  and `dart fix` carries the renames.
- **Breaking: a level's screens are texture views.** `LevelScene.screenOf`
  returns, and `LevelSceneParts.screens` holds, `RenderView`s made with
  `RenderView.texture` — `RenderTexture` folded into the view object in
  1.0. A screen's `texture`, `camera`, `excluded` and `invalidate` are where
  they were; `exposure` and `refreshEveryFrame` are in its `options`.

- **Breaking: a plugin's commands and components are published under its
  id.** Through a plugin's view of `EditorPieces`, `addCommand('sink', …)`
  registers `boats.sink` and `addComponent(kind: 'buoyancy')` registers
  `boats.buoyancy`, so a command or component the editor adds in a later
  minor never collides with a plugin's, and two plugins may both have a
  `sink`. A `PluginCommand`'s `name` is that published name. Palette entries
  stay keyed by the entity type they place, which is the level format's
  word. `EditorPieces.published` says what a name becomes.
- **The selection holds ids, not places in a list.** `Editing` keeps the
  primary and the others by the row's id and answers `selected` as the
  index the row has now, so a selection survives an undo that put a row back
  before it, and something whose id is gone is no longer selected.
  `selectedId`, `selectId` and `idOf` reach it directly, and `Listed` carries
  the row's `id`. What the editor adds or copies gets an id of its own; an
  unpacked prefab's entities too.
- **Breaking: overrides and template fields are addressed by id.**
  `setOverride`, `revertOverrides`, `applyOverrides` and `setPrefabField`
  store id paths, the way level format 3 keeps them, and still take a name
  or `#<index>` for any segment, looked up in the prefab it walks. `fields`
  lists an entity's properties beside its own keys, as before, and
  `setField` writes a property under `props`; neither shows the `id`.

- **Breaking:** `GeneratorException` extends `Flutter3dFormatException` instead
  of implementing `Exception` directly. The name and members are unchanged and
  every `on` clause that caught it still does; every exception the engine
  throws now hangs from `Flutter3dException` in `flutter3d_plugin_api`, in one
  of four families: format, capability, plugin and resource. A caller who
  reports anything the engine refused catches the root; one who acts on a kind
  catches its family. The migration table marks it as nothing to do.
- **A level's depth layers reach the renderer.** A brush surface's
  `depthLayer` is set on its batch's material (`Material.depthLayer`).
- **1.0.0 is a promise: strict semver from there.** This release candidate
  already keeps it. A patch fixes bugs and
  breaks nothing, a minor adds, and a break waits for a major. The whole
  public API is stable, with no experimental exceptions, and is held to the
  snapshot in `api/`. A deprecated name stays until the next major and for
  at least six months, and says what replaces it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#the-api-is-a-snapshot)
  has the rules, and
  [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)
  says which releases get fixes and on which platforms.

- **Prefabs in the editor.** `Editing.createPrefab` turns the selected
  entities into a prefab with one instance where they were;
  `placePrefab`, `setOverride`, `applyOverrides`, `revertOverrides`,
  `unpackPrefab` (one level down) and `setPrefabField` do the rest, each
  one step of undo, and each refused when the level would not expand.
  `prefabListing` prints every template path an override can name. The
  inspector has a Prefab section and offers a brush's `depthLayer`.

- **Breaking: seven new `EditorCommand`s** — `CreatePrefab`, `PlacePrefab`,
  `SetOverride`, `ApplyOverrides`, `RevertOverrides`, `UnpackPrefab` and
  `SetPrefabField`. An exhaustive `switch` over `EditorCommand` needs a case
  for each, or a default.

- **A placed thing keeps what its palette entry starts it with.** `Place`
  takes `properties:`, written only when there are any, so the editor places
  a plugin's palette entry with its defaults, and older placements read as
  before.

- **Breaking: `GeneratorSource` can no longer be implemented outside their own
  library: it is an `abstract base mixin class` now, so a game or a test mixes
  it in (`with`) and its class is `final` or `base`. A member added to it in a
  1.x release arrives with a body, which an `implements` could not have taken
  without breaking somebody.

- **A plugin brings its own commands, inspector sections and palette rows.**
  `EditorPieces` fills the plugin API's `EditorRegistry` slot: a plugin asks
  its host for `EditorPieces` and adds commands (`addCommand`, a name and a
  reader from JSON), components (`addComponent`, an `EditorComponent`: a
  heading, the fields it shows and their defaults, for one piece and,
  optionally, some entity types) and palette entries (`addPaletteEntry`, a
  `PaletteEntry`: an entity type, its label, tint and starting properties).
  Everything goes again when the plugin is switched off, and comes back in
  install order. A name, a component kind or a type somebody already holds
  is refused with the holder named.

- **Commands come in two families.** `DocumentCommand` is the sealed root
  with two branches: `EditorCommand`, the editor's own eleven, still sealed,
  so a `switch` over them stays exhaustive; and `PluginCommand`, open, for a
  plugin to extend. `EditorHistory.run` takes either, and
  `EditorPieces.readCommand` reads either back from JSON.

- **The inspector's sections are components.** `builtInComponents` lists
  the editor's own, and `inspectorSections` sorts a selection's fields into
  them, a plugin's components landing before the last section of their
  piece, which still takes every field no section names.
  `EditorPieces.offersFor` lists the fields a component offers that the
  selection does not have yet, at their defaults.

- **`paletteOf` takes the plugins' entries.** Its new `pieces` argument
  adds a row for each entry whether the level has one of its type or not,
  and `Placeable` carries the entry's `label` and `properties`, which a
  placed entity starts with when the level has none of its type to copy.

- **Undoing an inspector edit puts the field back.** It did not:
  `Level.toJson` hands back the same row maps on every call wherever nothing
  in them changed, the history's snapshot held those maps, and
  `Editing.setField` wrote into one of them, so the snapshot took the edit
  too and undo restored a document that already had it. `setField` now
  edits a copy of the row it changes.

- **More than one thing selected.** `Editing.selection` is the primary
  (`kind` and `selected`, as before) and whatever was added beside it with
  `Editing.toggle`, read against the document each time so nothing an undo
  took away stays selected. Selecting outright, adding, placing or
  duplicating drops the others. `MoveBy` moves all of them and `Delete`
  deletes all of them, each as one step of undo; with one thing selected
  both do what they did.

- **The level as a tree.** `outlineOf` lists the brushes, the lights and the
  entities by type, each row with a label and the kind and index that
  selecting it takes, and filters them by text. The editor's outliner is
  drawn from it.

- **`Editing.replaceLevel`** puts a whole level in place as one step of
  undo.

- **`LevelScene` builds a level's decals, mirrors and camera screens**:
  - a `DecalNode` from its material's picture, tipped onto a wall by
    `pitch`;
  - a `PlanarReflectorNode` on every batch of its material;
  - a `RenderTexture` that the material gives off as light.

- **Cutscenes are written like behaviours.** `Editing.cutscenes` lists the
  level's scenes by name; `setCutscene` reads a scene at
  `cutsceneStepsPerSecond` and writes it as a `cutscene` entity, refusing
  one that does not read, with where, or a name something else has;
  `removeCutscene` takes one out. Each is one step of undo.

- **Behaviour trees are written in the editor.** `Editing.setBehavior`
  writes a tree under a name and refuses one that does not read with every
  problem and where it is, writing nothing; `removeBehavior` takes one
  out. Each is a step of undo. `Editing.behaviorKinds` is what trees are
  read against, the standard kinds unless the game says otherwise, and
  `issuesFor` checks the level with `BehaviorsRead`.

- **The draw order of a brush, in the scene and the inspector.**
  `LevelScene` gives each batch its brushes' `drawOrder`, a duplicate keeps
  it, and the inspector offers it on a brush that has never said.

- **A scaffolded project asks for `^1.0.0`.** `pubspecFor` still wrote
  `^0.7.1`, so a game started from the template resolved the engine of two
  releases ago.

Its `flutter3d_*` dependencies ask for `^1.0.0`.

## 0.8.0+1

**Resolves on Flutter 3.44 and Dart 3.12.0.** The constraints asked for Dart
`^3.12.2` and `vector_math` 2.4.3, which were what this repository is built with rather than
what the package needs. A workspace that supports Flutter 3.44, Flame's among
them, could not depend on it. Nothing else changed.

## 0.8.0

**Breaking for an exhaustive `switch` over `EditorCommand`: `SetLights` is a
new case.** It puts a whole set of lights in place of the level's own as one
command and one step of undo, through the new `Editing.setLights`, and its
`why` names the step with the light optimizer's sentence. `editorCommandNames`
lists `setLights`. A light that was selected is deselected, since its index
may now name another light.

**`LightOptimizer` finds fewer lights that light a level the way it was
lit.** Every light is drawn alone from every view on the software rasteriser,
in linear light, so the pictures add exactly and the loss has an exact
gradient in each light's strength and colour. A greedy search removes the
most redundant light or merges a close pair into one, retunes the rest with
Newton steps per channel, and keeps a move while the picture stays within
`maxDifference` (0.01, about two and a half 8-bit steps) and no more than
`maxUnderLit` (0.01) of the lit pixels fall below `darkening` (0.75) of their
brightness. `optimize(level, views:, states:)` returns a `LightPlan` with the
lights `before` and `after`, the `moves` as sentences, shading cost, overlap,
`difference`, `underLit` and previews. The new set is drawn for real and held
to the same bounds, and `holds` says whether it stayed inside them; a plan
that did not has `changes` false. Each `LightingState` is a set of lights the
level is also judged under, so a lamp the noon sun drowns out is still kept
for the night. Views come from `viewsAlong`, over poses a player walked, or
`defaultLightViews`, four headings from each spawn. The trigonometry and the
sRGB decode go through `Portable`, so the answer is the same on every
machine. Nothing runs until it is called. A call draws each light once per
view at 160 by 100, plus one draw per view for each merge it tries, up to
`maxMerges` (16). `N1`

**`LevelScene` builds a level's scene without Flutter.** The brush meshes,
materials, lights and probes moved here from `flutter3d_app`'s `LevelLoader`,
which now hands it the textures it decoded, so a program started with
`dart run` can draw a level. `LevelScene(batching:)` takes a `LevelBatching`:
`perMaterial`, the default, groups brushes per material as before, and
`perBrush` makes every brush its own draw so a pixel can name its brush, at
the cost of a draw per brush. `meshDataOf` moved here too. `LevelScene` draws
the brushes it is given, so a caller expands a level's recipes first.

**`Editing.addRecipe` adds a room, a corridor or a scatter from a seed.** It
expands the recipe once before adding it, so a recipe no kit can build throws
the kit's `LevelFormatException` and leaves the document and the undo stack as
they were. The document keeps the recipe, and `vocabularyOf` now names the
entity types the recipes expand to, so a room's reflection probes are no
longer reported as unknown entities.

**Level generators are Dart.** `DocumentText` writes a document in the exact
layout the shipped levels use, `LevelGenerator` is a function from a
`GeneratorSource` to text by path, `GeneratorRefused` is how a generator
refuses, and `roundNumber` keeps an `int` an `int`. The library still reads
and writes no file. The generators of every shipped level live under
`tool/levels` and regenerate each tracked document byte for byte; they replace
the Python scripts that wrote them.

`flutter3d_cpu` is a new dependency, for the optimizer. The package still
imports no Flutter.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**New projects ask for `^0.7.1`.** The scaffold templates wrote `^0.7.0`,
which resolves to a release that does not build from pub.dev.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3.

## 0.7.0

* **`scaffold` writes a project against the packages that exist now.** The
  pubspec it generates names `flutter3d`, `flutter3d_game`, `flutter3d_sim`,
  `flutter3d_app` and `flutter3d_audio` at `^0.7.0`. 0.6.0 wrote
  `flutter3d_bridge` and `flutter3d_session` into it, which are discontinued
  as of this release, and did not name `flutter3d_sim`, which
  `flutter3d_game` no longer re-exports. A project scaffolded by 0.6.0 keeps
  resolving against 0.6.0; `doc/boundary-0.7.0.md` lists which import lines
  move when it is brought up.
* **`isDirty` compares documents, not depths.** After an undo or a redo it was
  whether the undo stack's length differed from its length at the last
  `saved()`. Save, undo one step, make a different edit, undo that and redo
  it: the stack is as deep as it was at the save, and 0.6.0 read clean over a
  document that was never written. Every new document now gets a token, undo
  and redo carry theirs with them, and `isDirty` is whether the current token
  is the saved one. Undoing back to the saved document still reads clean.
* **A `.fmat` is edited through a gate, and the gate is here.**
  `materialWith(document, key, value)` returns the `MaterialDocument` with one
  field changed, or null when the result is not a file `readFmat` takes as
  written: the value does not fit the hint's shape, reading it back warns
  about something new, or the value comes back different. A value outside a
  range hint's ends is not refused, because a hint describes a control and
  does not constrain the reader. `materialDocumentFields` and
  `materialDocumentHint` came with it. They were private to the model editor's
  material panel and could move once `MaterialDocument` was in a plain Dart
  library, so `flutter3d_core` `^0.7.0` is a dependency now, for
  `package:flutter3d_core/formats.dart`.
* **What a lesson's step panel computes, without the panel.** `orderedSteps`,
  `mergedOffsets`, `movedStep`, `freshName` and `indexOfNamed` produce the
  values `Place` and `SetField` are handed for an `edu_sequence` and its
  `edu_step`s; none of them is a new `EditorCommand`. `bindingsInLevel` returns
  every binding an `edu_step` declares, keyed by target, as `ActiveBinding`s,
  which is what an inspector needs to know before it draws a property as
  read-only because a data source will overwrite it.
* Still plain Dart. The floor on `flutter3d_sim` is `^0.7.0`. The archive
  carries `skills/flutter3d-editor-core-editing-a-level/` for a coding agent,
  installed with `dart run skills@ get`.

## 0.6.0

**The first release. It takes the set's number rather than a first number of its
own**, because the whole workspace goes out together and a document layer
resolved against a different `flutter3d_sim` than the editor above it would be
reading a level format nobody built it against. What follows is what this
package is, not what changed in it: the two versions it wore inside the
repository were never uploaded.

* **The headless half of a level editor, and the reason it is a package is that
  nothing could depend on it.** `Editing`, `Handle`, `Picking`, `Placeable`,
  `Looks`, `OpenKind`, `Template` and `scaffold` were files in an application
  that named Flutter nowhere at all. Anything else that wanted them — a
  command-line linter for a level, a tool an agent speaks to, a service that
  validates an uploaded level before a player loads it — had to depend on an
  application, which pub cannot express and this repository's own rules forbid.
* **Plain Dart, and the boundary is checked rather than described.** Every type
  the document is made of — `Level`, `Brush`, `LevelLight`, `EntityDef`,
  `EntityRegistry`, `LevelValidator`, `LevelIssue` — comes from `flutter3d_sim`,
  which stopped needing Flutter when it was split out. A rule in
  `tool/structure.dart` reads this package's `lib/` and `test/` and fails on the
  first `package:flutter/`, `package:flutter_test/` or `dart:ui`.
* **A change to a document is a value, not only a method call.** `EditorCommand`
  is a sealed hierarchy of ten — `MoveBy`, `Resize`, `AddBrush`, `AddLight`,
  `Place`, `Duplicate`, `Delete`, `SetField`, `Brighten`, `Turn` — each with a
  `says` that reads as a sentence, a `toJson` and a `fromJson`. That buys what a
  method cannot: the set can be listed, so a tool server builds its table from
  `editorCommandNames`; a step can be named, so undo says what it took back
  rather than the word "undone"; and a call can arrive over a socket, which is
  the whole shape of driving this editor from outside it.
* **Nothing reverses itself, and that is the decision.** The obvious form for a
  command is a pair — do it, undo it — and there is deliberately no second half.
  Going back is implemented once, in `EditorHistory`, by putting a snapshot of
  the whole document back: a level is a few hundred numbers and a snapshot costs
  nothing worth measuring, while an inverse per command is ten more places for
  the way back to disagree with the way there. The disagreement shows up as
  somebody's brush a quarter of a metre from where they left it rather than as a
  crash, which is why it is not a bug anybody would find.
* **A transaction, because a drag was eating the stack.** Dragging a brush across
  a room is one thing a person did and a hundred changes to the document;
  recorded singly they filled all sixty-four steps in about a second, so the
  change anybody would actually want back was gone before the mouse button came
  up. `EditorHistory.transaction` takes one snapshot on the way in and leaves at
  most one step on the way out — at most, because a drag that never left the
  grid square it started in is not a change, and an undo that has to be pressed
  twice is an undo nobody trusts.
* **"Is there unsaved work" is answered where the stack is.** `EditorHistory`
  holds the undo stack, the redo stack and the depth the stack stood at when the
  file was written; undoing back past a save answers no and redoing forward past
  it answers yes again. `Editing.undo`, `redo`, `canUndo`, `canRedo`, `isDirty`
  and `saved` still stand in front of it and answer the same way.
* **A scaffolded project names hosted versions, and they are this release's.**
  `pubspecFor` writes `^0.6.0` rather than a path into the checkout, so a new
  game travels off the machine that made it. The floors move with the set for a
  reason worth stating: a caret below 1.0.0 stops at the minor, so a seed left
  at an old line hands its author the engine of that month — it compiles, it
  runs, and the first news of how old it is comes from a name in a tutorial that
  is not there.
* **What is deliberately not here.** A camera, because that reaches for a
  renderer, and reading a file off a disk, because a headless core has no
  business doing it. Both stayed in the application this package left.

