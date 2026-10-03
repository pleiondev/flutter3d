## Unreleased

- **The rest of the scene as widgets** — `P10`. `Material3D` is a material
  as a widget: the `Mesh3D`s below it without a material of their own are
  drawn with the one engine material it makes, changed in place on a
  rebuild so they keep it and the batching keeps seeing one.
  `ReflectionProbe3D`, `Decal3D`, `Mirror3D` (the meshes directly below it
  are its surfaces, joining and leaving with their widgets) and
  `Particles3D` (an effect at a rate, emitted at the node and advanced with
  the scene) join `Mesh3D`, `Light3D`, `Camera3D` and `Model3D`;
  `Contributor3D` adds any pass contributor while it is in the tree.
  `SceneWidgets.mount` builds the same widgets into a scene somebody else
  draws, with no screen — a golden runner, a test, a game with its own loop.
  `Scene3D` now disposes the renderer it made and the device it opened.
  `example/lib/widgets_main.dart` is `minimal_main.dart` written this way,
  and `widget-scene` is drawn from widgets in all four golden sets.

- **The software backend draws a material's lighting hook.**
  `MaterialProgramStage` applies the maps and gathers the lights through
  the material's `light` block with `accumulateLights`, then hands the
  fragment body `lit` — the same sum the emitted shader makes. A `light`
  block returning the albedo draws pixel for pixel what the built-in
  Lambert does.

- **`HotMaterials.bind(material, name)`** keeps a material drawn with a
  bundled `.f3dmat` across hot reloads — `P8`. After an edit the hook
  compiled, a bound material gets the lighting model the new source
  describes and a default for a uniform it now declares, keeping the values
  the game set; an edit that starts sampling a map or declares a uniform
  used to reach only the materials the game gave the new model by hand.

- **A scene written as widgets** — `P10`. `Scene3D` opens a device, makes a
  renderer and a scene and draws them; `Mesh3D`, `Model3D` (loaded
  asynchronously, with a placeholder, its animation clip, speed and pause as
  properties), `Light3D`, `Camera3D` and `Node3D` below it each own one node
  of that scene. Reconciled by Flutter's own keys, so a rebuild keeps each
  node and what a game set on it; a shape made fresh in `build` is uploaded
  again only when its vertices change. Suffixed `3D` because `SceneNode` is
  the engine's own class.

- **`HotSwap.loadMaterial`** loads the bundle the build hook compiled a
  `.f3dmat` into and watches it — `P8`: the library for the renderer, the
  materials' lighting models and parameters, and an edit drawn by the next
  frame after a hot reload, on the software backend too.

- **The software material stage reads a `uniform`** from the draw's
  `MaterialParams`, as the GLSL does.

- **`MaterialProgramStage` and `materialLanguageCompiler` moved here** from
  `flutter3d_testing`, so a game can depend on them, and the software backend
  this package registers compiles a bundle's material-language stages.

- **A photo goes somewhere.** `takePhoto` draws with `capturePhoto`, encodes
  with `PngStripWriter` and puts the file on a `PhotoShelf`, abandoning it if
  the capture fails. `FilePhotoShelf` writes into the player's Pictures folder
  on a desktop and the game's own folder on a phone, through a `.part` file and
  a rename. `BrowserPhotoShelf` offers the share sheet where the browser takes
  files and downloads otherwise. `defaultPhotoShelf` picks the platform's.

- **A tool attached to a running game can read the game's own frame.**
  `registerRenderExtensions` puts `ext.flutter3d.render.passes`,
  `passOutput`, `draws`, `draw`, `readPixel`, `scanNan` and `stats` on the VM
  service, each answered from a capture of the next frame the game draws, so
  what comes back is the GPU frame with its passes, targets and draws rather
  than a second picture drawn on the software backend. The answers are
  worked out by `renderPasses`, `renderDraws` and the rest, plain functions of
  a `FrameCapture` that a test calls directly. `scanNan` reports a float
  target it could only read as bytes as unread rather than clean: a NaN
  clamps to an ordinary byte on every hardware readback.

- **A texture repainted under a running game is drawn at whatever size it
  now is.** `HotSwap.loadTexture` and `registerTexture` watch an image file;
  a swap after it changed uploads the new picture as a texture of its own,
  puts it where the old one was in every material of the registered scenes
  and in their environment, and releases the old one once no frame in flight
  samples it. `SwappableTexture.changes` tells anything else holding it.
  `LevelLoader` watches every map a level names, and `LoadedLevel.dispose`
  stops. `ext.flutter3d.assets.put` accepts an image registered this way.

- **A shader parameter dragged in the editor changes the next frame.**
  `HotSwap.setMaterial` takes `parameters/<name>` beside the built-in
  fields and writes the numbers into the list `Material.parameters` already
  holds, which the renderer binds every frame. A parameter the material was
  not loaded with, or a list of another length, is refused with what the
  material does have. A level material that defers to a `.fmat` is now
  called by the level's name for it rather than the file's, so the editor
  reaches it by the name it knows.

- **A sky panorama edited under a running game lights it again.**
  `HotSwap.loadEnvironment` builds the prefiltered cube a `.hdr` or an image
  asset makes, whose roughest level is also the irradiance, and
  `SwappableEnvironment.applyTo` puts it on a scene. A swap after the file
  changed prefilters it again and puts the new cube, with its level count,
  on every registered scene that was lit by the old one; the old cube goes
  back to the device after its frames, as a swapped texture does.
  `registerEnvironment` takes an environment built some other way, the
  report lists what changed under `environments`, and
  `ext.flutter3d.assets.put` accepts a panorama registered either way.

**A hot reload shows the shaders it reloaded.** Flutter 3.47 reinitializes an
asset-loaded shader bundle on hot reload, which the engine's own bundle is,
but a pipeline linked from the old code went on drawing it: the library
changed and the picture did not. `HotSwap` relinks every renderer
it knows of on a reload, and refreshes the bundles an application loaded
from bytes and registered with `registerLibrary`, which Flutter's reload
never reaches. A bundle that does not load keeps the last one that did and
is named in the report. `SceneSurface` registers its renderer and reloads
from `reassemble`, so a game drawn through it, the Flame bridge's included,
needs nothing more; a tool reaches the same reload as
`ext.flutter3d.hotSwap`. Debug builds only: in profile and release it holds
nothing.

**A model edited while the game runs is drawn in the nodes the game
holds.** `HotSwap.loadModel` hands back a `SwappableModel`; instances made
through it adopt the new file on the next hot reload, keeping their nodes,
transforms and animation. `ext.flutter3d.assets.put` sends a model's bytes
over the VM service instead, for a device whose disk the editor cannot write.
A model that does not build keeps the version that did.

**A material dragged in an inspector changes the next frame.**
`HotSwap.setMaterial` (`ext.flutter3d.material.set` over the VM service)
sets base colour, emissive, roughness, metallic, normal scale or alpha cutoff
on every material of that name in the scenes registered — `SceneSurface`
registers its own — and keeps them as overrides that a model swap does not
undo. `clearMaterial` lets them go.

`SceneSurface` is a `StatefulWidget` now, for `reassemble`. Its constructor
and parameters are unchanged.

## 0.8.1+1

**Resolves on Flutter 3.44 and Dart 3.12.0.** The constraints asked for Dart
`^3.12.2`, `vector_math` 2.4.3 and `clock` 1.1.3, which were what this repository is built with rather than
what the package needs. A workspace that supports Flutter 3.44, Flame's among
them, could not depend on it. Nothing else changed.

## 0.8.1

**`SceneSurface` draws more than one view.** `moreViews` are drawn into the
same frame after `view`, each through its own camera into its own part of
the frame: the other half of a split screen, a rear-view mirror. The
renderer drew several views and the surface handed it one, so a two-player
game had to leave the widget and drive the renderer itself.

## 0.8.0

**`LevelLoader` builds the scene through `flutter3d_editor_core`'s
`LevelScene`.** The part of loading that turns a level into brush meshes,
materials, lights and probes moved there, so a program started with `dart run`
can draw a level too. `LevelLoader` keeps the asset bundle and the image
decoding, hands what they produced to `LevelScene`, and wraps the result in
`LoadedLevel` as before; a game gets the same scene. Its public helpers
forward to the new home, and `meshDataOf` is still exported from here.
`flutter3d_editor_core` is a new dependency.

**`LevelLoader.load` takes `batching` and `deviceClass`.** `batching:
LevelBatching.perBrush` makes every brush its own draw so a tool can name the
brush under a pixel; the default, `LevelBatching.perMaterial`, draws as
before, and `LoadedLevel.batching` keeps the choice so a rebuild after a
breach groups brushes the same way. `deviceClass`, or the application's
`assetDeviceClass` when it is left out, reads `crypt.phone.json` before
`crypt.json`, which is the file `flutter3d_build`'s `lights --classes` writes
with the light set that class affords. The visibility table and the lightmap
are shared by every class. With no class picked the loader reads what it read
before. `N7`

**A level's `recipes` are built when it loads.** A room, a corridor or a
scatter written as a recipe is expanded into brushes, entities and lights
before the level is validated and drawn.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**A widget drawn into a scene is unmounted when it goes.** `WidgetSurface` and
`WidgetTexture` only finalized their tree, so no `State.dispose` ran and every
ticker, controller and focus node stayed alive. `WidgetSurface` also releases
the texture it replaces and its mesh, and ignores an upload that lands after a
newer frame or after `dispose`. Textures bound for a level's `.fmat` materials
and every terrain tile mesh are released with the level.

**`ModelVisuals` and `PropVisuals`**, for a level's `model` and `prop`
entities, live here beside `LevelLoader`. A `model` entity is a whole decoded
hierarchy, so a lesson step can address a node inside it. Its asset loads
through `loadModelByPath`, so an `assets_src/` path the build hook converted is
found, and a model that finishes decoding after `dispose` is released instead
of added to a scene nobody draws.

`SceneSurface` clamps an unbounded constraint before rounding it and no longer
throws inside a `Column`, and the level loader reads a `ByteData` view rather
than its whole backing buffer.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `clock` ^1.1.3, `vector_math` ^2.4.3.

## 0.7.0

**Breaking.** What any application needs from `flutter3d_session` and
`flutter3d_bridge` is here now, and nothing is re-exported.
`doc/boundary-0.7.0.md` has the whole list of packages that were folded for
this release. `flutter3d_backend`, `flutter3d_session`, `flutter3d_screens` and
`flutter3d_bridge` are marked `discontinued` on pub.dev the day this is
published, and an import of one of them moves to this package or to
`flutter3d_game`.

* From `flutter3d_session`: `SceneSurface`, `FrameClock`, `FrameTimingLog`,
  `DidNotStart`, and `WidgetSurface` with its pipeline.
* From `flutter3d_screens`, which was folded into `flutter3d_session` first
  and followed it: the status screens `LoadingScreen`, `RendererFailure` and
  `LevelLoadFailed`, and `Storage`/`BinaryStorage`, with the atomic write in
  `package:flutter3d_app/native.dart`.
* From `flutter3d_bridge`: `LevelLoader`, `LoadedLevel`, `SharedMeshes`,
  `SurfaceMesh`, `VisibilityCuller` and `WidgetSurfaceVisuals`.
* From `flutter3d_game`: `Issue`, `IssueSink` and `IssueLog`, which a storage
  reports through.
* No longer re-exported: `flutter3d_session`, `flutter3d_screens`, `pad_input`
  and `pointer_lock`. What a game took from the first two, `RunSession`,
  `SaveFile`, `SettingsFile`, the settings panel and rebinding among it, is
  `flutter3d_game` now, and a game names the two device packages itself.

**Breaking.** Accepted `flutter3d_backend`, because most of its consumers
already reached it through this barrel rather than by naming it, and the
handful that still named it directly — two package examples, and one game's
now-redundant line — cost nothing to repoint, which left the separate
package with no boundary of its own (package-merge-plan.md §3.6). The
conditional export deciding which backend a
build draws through — `openDevice`, `kFixedResolution` — now lives directly
in this package's own `src/backend_native.dart`/`src/backend_web.dart`, and
this package depends directly on `flutter3d_hardware`, `flutter3d_impeller`,
`flutter3d_webgl`, `flutter3d_cpu` and `flutter3d_webgpu` instead of on
`flutter3d_backend`. Nothing an application imports changed, unless it named
`package:flutter3d_backend/flutter3d_backend.dart` itself; that line becomes
`package:flutter3d_app/flutter3d_app.dart`.

**`presentFrame(device, frame, {fit, quality})`, new — a registry lookup, not
a fixed list.** `GraphicsDevice.present` is gone (mcp-01n), and what replaces
it is `flutter3d_hardware`'s own device registry: `registerBackendOpener` and
`registerDevicePresenter`, which every backend — including a third-party one
this repository has never heard of — calls on itself. `flutter3d_impeller`
and `flutter3d_webgl` register both halves from their own packages;
`flutter3d_cpu` registers only its opener, since the flat package that went
through mcp-02n cannot also build a Flutter `Widget` for `CpuFrame`, which
moved here. This package's `openDevice`/`presentFrame` are the batteries-
included default: they make sure the four backends this repository ships
have registered themselves, then hand the question to the registry — a
caller who wants a fifth backend, or none of these four, can register
directly with `flutter3d_hardware` and never name this package at all.

**Breaking. `SceneSurface` takes `presentFrame`.** It is a required constructor
argument of type `FramePresenter`, so every existing `SceneSurface` call site
needs one line added: `presentFrame: presentFrame`. It became a parameter while
the widget lived in `flutter3d_session`, which this package depended on and
which could not name this package back. The widget is here now and the
parameter stayed as it was.

**A widget can be a texture, and a mesh in a level.** New since 0.6.0, and
arriving here with the session half. `WidgetTexture.draw` rasterises one widget
off the tree at the size asked for and uploads the pixels, for a sign whose
text changes once a lap. `WidgetSurfacePipeline` keeps a `BuildOwner`, a
`PipelineOwner` and a `RenderView` alive between frames, repaints when one of
them says something changed, and takes a pointer at a UV through
`dispatchAtUv`, which hands it to `GestureBinding.dispatchEvent`, so an
ordinary `GestureDetector` or `TextField` answers it. `WidgetSurface` is a
`MeshNode` carrying that canvas as its albedo. `WidgetSurfaceVisuals` resolves
a level's `widget_surface` entities against a `Map<String, WidgetBuilder>` the
application hands over, and `WidgetSurfaceKind` is the `EntityKind` a game
registers so that a level naming the type loads. It spawns nothing.

**`BinaryStorage`, for a document that is bytes and may be megabytes.** The
same shape as `Storage`: read, write, remove, a name, and it never throws.
`defaultBinaryStorage(appName)` answers `FileBinaryStorage` on native
platforms, with the atomic write the text storage has, and
`IndexedDbBinaryStorage` on the web, since `localStorage` holds a few megabytes
for everything an origin keeps. `applicationFolder(appName)` is the directory
the files are in, and null in a browser.

**A storage name that holds a directory is written.** `FileStorage` and
`FileBinaryStorage` created their root and then wrote into a subdirectory
nothing had made, so a name such as `autosave/<hash>` failed with "No such file
or directory" on every write and answered false. Both create the file's own
parent now.

**`LevelLoader.load(sidecars:)`.** True by default. With false the loader does
not ask for a level's visibility table and lightmap. A circuit in the open air
has neither: the racing demo's ring baked to a table in which every pair of
cells sees every other, and asking for it cost two 404s in the console of every
web build.

**`TerrainTiles` draws a `HeightfieldTiles` with detail that follows the
camera.** One `MeshNode` per tile in `nodes`, a `TileLevelChooser` deciding the
level per tile, and `update` pointing each node at the mesh for the level its
distance calls for. A level's mesh is uploaded the first time a tile needs it
and kept, and `uploads` counts them. `flutter3d_sim` 0.7.0 has the tiles, the
skirts that close a seam between two levels and the chooser's band.

**`SceneSemantics` describes the scene to a screen reader.** A viewport is a
texture, so the accessibility layer saw one image the size of the window.
`semanticObjectsFor` projects each `SceneAnnouncement`'s node through
`screenBoundsOfBox` and answers a `SemanticObject` with a rectangle, a label, a
hint, a three-valued `selected` and an `onTap`; `SceneSemantics` lays one
semantics node over each. The nodes sit under `IgnorePointer`, so they take no
gesture from the viewport, and the picture under them is wrapped in
`ExcludeSemantics`. A node with no bounds is left out, and a box the camera is
inside answers the whole viewport.

**`MemoryPressureRelease` gives the pooled render targets back on a memory
warning.** A widget around the scene that observes `didHaveMemoryPressure` and
calls `Renderer.releaseTransientTargets`, with an optional `onReleased`.
Targets lent to a frame in flight are left alone, and the frame after a release
is byte for byte the frame before it.

**The software backend's picture no longer freezes on its first frame.**
`CpuFrame`'s presenter decoded its texture only when the texture instance
changed, and `flutter3d_cpu` hands back the same render target every frame, so
the widget went on showing the frame it started with. The two GPU backends
present through their own path and were not affected.

**What it depends on.** `flutter3d`, `flutter3d_hardware`, the four backends
and `flutter3d_sim` at `^0.7.0`, with `clock`, `vector_math` and `web`.
`pad_input` and `pointer_lock` are no longer dependencies.

## 0.6.0

* **Floors, and no code.** Storage, settings, the frame clock and the screens
  are byte for byte 0.5.0's. `flutter3d_backend`, `flutter3d_session` and
  `flutter3d_screens` move to `^0.6.0`; `pad_input` and `pointer_lock` stay at
  `^0.4.0`, which their 0.4.1 covers.
* **What arrives through the barrel is one line wider without this package
  changing.** `flutter3d_backend` 0.6.0 can try WebGPU on a web build given
  `--dart-define=FLUTTER3D_WEBGPU=true`; an application assembled from here
  gets that by raising the floor and nothing else, because `openDevice` was
  always the whole of the question this layer asks.

## 0.5.0

* No API change. Its floors move to the 0.5.0 packages it assembles.

## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* A barrel over `flutter3d_backend`, `flutter3d_session`, `flutter3d_screens`,
  `pad_input` and `pointer_lock` — the five packages an application assembles
  itself from, none of which know about each other. No code of its own.
