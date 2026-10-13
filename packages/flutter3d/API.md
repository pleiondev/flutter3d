# The flutter3d API

This is the public API of flutter3d 1.0.0-rc.1 for an application or a game:
what each package is for, the types an application meets first, and what
each area may gain in a 1.x minor. It is a map, not a copy of the API
reference. Every name here is in a committed snapshot under
`packages/<package>/api/<package>.api`, and the generated reference at
<https://flutter3d.pleion.dev/docs> has every member.

The plugin and extension API (what a plugin is written against, and every
hook it can implement) is a document of its own:
[`flutter3d_plugin_api/API.md`](../flutter3d_plugin_api/API.md).

Contents:

1. [Packages and layers](#packages-and-layers)
2. [Entry points](#entry-points)
3. [Scenes and nodes](#scenes-and-nodes)
4. [Assets, formats and loading](#assets-formats-and-loading)
5. [Materials](#materials)
6. [Lights and cameras](#lights-and-cameras)
7. [Render settings and post effects](#render-settings-and-post-effects)
8. [The simulation loop](#the-simulation-loop)
9. [Physics](#physics)
10. [Input and actions](#input-and-actions)
11. [Audio](#audio)
12. [XR](#xr)
13. [Tools for editors and agents](#tools-for-editors-and-agents)
14. [Plugins](#plugins)
15. [Errors and refusals](#errors-and-refusals)
16. [Lifecycle and disposal](#lifecycle-and-disposal)
17. [Units](#units)
18. [Versioning, stability and migration](#versioning-stability-and-migration)

## Packages and layers

The engine is a stack of packages, each of which depends only on the ones
below it. An application usually imports one or two facades and names a
lower package only for a type the facade does not carry.

| Layer | Packages | Role |
|---|---|---|
| Foundation | `flutter3d_foundation` | Values every package speaks: `Flutter3dException` and its families, `WorldPosition`, `LinearColor`, `Quantity` and `Unit`, the file envelope (`FormatSpec`, `FormatDocument`), `Registration`, `Issue`, `EngineLog`, the expression language |
| Matter | `flutter3d_matter` | `WorldProperties`, `MaterialCatalog`, `PhysicalMaterial`, `MatterState` |
| Hardware | `flutter3d_hardware` | The HAL: `GraphicsDevice`, encoders, handles, formats, `DeviceFeature` |
| Backends | `flutter3d_impeller`, `flutter3d_webgpu`, `flutter3d_webgl`, `flutter3d_cpu` | One implementation of the HAL each; `flutter3d_app` picks one at run time |
| Renderer | `flutter3d_core` (with `geometry.dart` and `formats.dart`), `flutter3d` | The scene graph, the frame graph, materials, animation, model and texture formats; `flutter3d` adds what needs Flutter (the asset bundle, image decoding) |
| Plugin contract | `flutter3d_plugin_api`, `flutter3d_fields`, `flutter3d_plugin_runtime` | What a plugin is written against; see [the plugin API](../flutter3d_plugin_api/API.md) |
| Simulation | `flutter3d_physics`, `flutter3d_physics_native`, `flutter3d_sim` | Collision and dynamics (Dart and C cores), the fixed-step loop, input, levels, saves, tapes, replays. Plain Dart, no Flutter |
| Application | `flutter3d_app` | The view widget, the backend choice and fallback, level loading, storage, widgets in the scene, XR |
| Game | `flutter3d_game` | Input bindings, settings, saves, the run session, actor and fixture visuals |
| Extras | `flutter3d_audio_core`, `flutter3d_audio`, `flutter3d_particles`, `flutter3d_post`, `flutter3d_camera`, `flutter3d_game_*`, `flutter3d_net`, and the rest | Features installed by import, most of them as plugins |

The site's [package index](https://flutter3d.pleion.dev/reference/packages/)
describes every package.

### The three facades

| Import | Exports | Use it for |
|---|---|---|
| `package:flutter3d/flutter3d.dart` | By name: the renderer and formats of `flutter3d_core`, the HAL vocabulary of `flutter3d_hardware`, the foundation values, the fields (`FieldDeclaration`, `Subsystem` and the rest), `flutter3d_matter`'s materials and world, `flutter3d_hub`'s references, and the plugin contract's core types (`Flutter3dPlugin`, `PluginManifest`, `LoopPhase`, `SimulationProfile`, `PublishedState`). Declares `ModelAsset`, `loadModelByPath`, `bindMaterial`, `BundleAssetSource` and the `Color` conversions | Anything that draws |
| `package:flutter3d_app/flutter3d_app.dart` | Declares `Flutter3dView`, `Scene3D` and the widgets under it, `SceneSurface`, `openDevice`, `LevelLoader`, `Storage`, `HotSwap`, the XR types. Re-exports the few simulation names the view's settings spell (`EngineLoop`, `InputState`, `TimeSource`, `WorldTiming`, `Level`) | An application, a tool or a viewer, imported beside `flutter3d` |
| `package:flutter3d_game/flutter3d_game.dart` | Everything `flutter3d` exports, the view from `flutter3d_app`, and by name the loop, the level, input, saves and tapes from `flutter3d_sim`, the collision world, colliders and dynamics from `flutter3d_physics`, the listener, emitters and sound bank from `flutter3d_audio_core`, the particles. Declares input bindings, settings, saves, `RunSession`, `RunTimeline` | A game: one import for most of it |

Each facade re-exports with a `show` list, so a name added to a lower
package reaches the facade only when somebody lists it. A structure rule
holds each list closed: every type a facade's API names, in a signature, a
typedef's function type or a generic argument (`EventHandler` names
`Delivered`, `Dynamics.forces` names `BodyForce`), is exported by the
facade too. So a game handling a contact needs only the one import:

```dart
import 'package:flutter3d_game/flutter3d_game.dart';

void listen(EngineLoop loop, Dynamics dynamics, void Function(Object?) hit) {
  loop.events.onStep<ContactEvent>('hits', (Delivered<ContactEvent> d) {
    if (d.event.phase != ContactPhase.begin) return;
    // The ids the event carries, read back to the body and its actor.
    hit(dynamics.bodyOfId(d.event.bodyB)?.collider.userData);
  });
}
```

Import a lower package when:

- the type is in no API the facade exports, so not in its `show` list (the
  snapshot of the facade, `api/<facade>.api`, lists them);
- the code must not depend on Flutter: a server, a CLI or a test under
  `dart test` imports `flutter3d_sim`, `flutter3d_physics` or `flutter3d_core`
  directly, since the facades pull in Flutter;
- the code is a plugin: it imports `flutter3d_plugin_api` and what it
  registers into, never a facade.

A backend is never re-exported. `flutter3d_app` chooses among them at run
time; an application that names one adds it to its pubspec.

**What grows in 1.x.** A facade may list more names. A name is never taken
off a facade within 1.x.

## Entry points

There are three ways to put a scene on screen, from the most assembled to
the least.

### `Flutter3dView`

The widget most applications start from (`flutter3d_app`). It opens the
device (the GPU where it starts, the software rasteriser where it does not,
with a closable banner), makes the renderer and the loop, warms the scene's
pipelines a slice at a time, and owns the frame clock, focus, pausing,
restoration and teardown.

| Member | Type | What it is |
|---|---|---|
| `scene`, `camera` | `Scene?`, `CameraNode?` | What is drawn and from where |
| `device` | `DeviceSettings` | The device and renderer, borrowed or opened; `onDeviceLost`, `onDeviceRestored`, `fallbackBanner`, `presenter` |
| `view` | `ViewSettings` | `settings` (`RenderSettings`), `render` (`RenderViewSettings`), `resolution` (`ViewResolution.native`, `.capped(pixels)`, `.scaled(factor)`), `views`, `continuous`, `frameRateCap`, `placeholder`, `failure`, `warmUp`, `onWarmUpProgress` |
| `loop` | `LoopSettings` | `timing` (`WorldTiming`), `input`, `drainLook`, `originShift` (meters, 1000 by default, `null` off), `simulation` (`SimulationPlacement`), `profile` (`SimulationProfile`) |
| `plugins` | `PluginSettings` | `plugins`, `formats`, `registries` handed to the loop |
| `time` | `TimeSource?` | How many steps a frame brings (see [the simulation loop](#the-simulation-loop)) |
| `xr` | `XrSettings?` | An XR session to draw into (see [XR](#xr)) |
| `onCreated` | `void Function(Flutter3dEngine)` | Once, when the device, renderer and loop exist |
| `onBeforeFrame`, `onFrame` | `void Function(EngineFrame)` | Before and after each frame |
| `saveState`, `restoreState`, `restorationId` | | State restoration |
| `onPausedChanged`, `onListenerMoved`, `onKeyEvent`, `focusNode`, `autofocus`, `log` | | Pausing, the audio listener's pose, keys, focus, the engine log |

The four settings groups are `final` classes with `const` constructors and
`copyWith`, which is where an option a minor adds lands, with a default.

`Flutter3dEngine`, handed to `onCreated` and in every `EngineFrame`, holds
what the view made: `device`, `renderer`, `scene` (settable), `camera`,
`view` (`RenderView`), `loop` (`EngineLoop`), `simulation`
(`SimulationHandle`), `published` (a `ValueListenable<PublishedState>`),
`devices`, `log`, `backendRefusals`, `loss`, and `ownsDevice` and
`ownsRenderer`.

```dart
Widget view(Scene scene, CameraNode camera) => Flutter3dView(
  scene: scene,
  camera: camera,
  view: const ViewSettings(resolution: ViewResolution.capped(1920 * 1080)),
  loop: const LoopSettings(timing: WorldTiming(stepRate: 120)),
  onCreated: (Flutter3dEngine engine) => engine.loop.addSystem(
    'spin',
    LoopPhase.movers,
    (step) => _spin += step.dt,
  ),
  onFrame: (EngineFrame frame) {},
);
```

### `Scene3D` and the scene widgets

`Scene3D` is the same view with the scene written as widgets. It takes the
same four settings groups, handed on whole, plus `children`, `clearColor`,
`materials` (a `ShaderLibrary`) and `onSceneCreated`
(`Scene3DController`: `engine`, `scene`, `camera`, `device`, `renderer`).

| Widget | What it puts in the scene |
|---|---|
| `Node3D` | A transform with children |
| `Mesh3D` | A mesh from a `Shape` or a `MeshGeometry`, with a `RenderMaterial`, `castsShadow`, `drawOrder`, `onTap` (a `Tap3D`: `hit`, `localPosition`, `kind`, `buttons`) |
| `Model3D` | A model from `source` (a path) or `load`, with `animation`, `playing`, `speed`, `placeholder`, `onLoaded` (`ModelInstance`), `onProgress` (`AssetProgress`), `onError` and `errorBuilder` (a `Model3DFailure`: `error`, `stackTrace`, `source`), `onTap` (a `Tap3D`) |
| `Material3D` | One `RenderMaterial` shared by the meshes below it, changed in place on rebuild |
| `Light3D` | A light: `.sun()`, `.directional()`, `.point()`, `.lamp()`, `.spot()` (inner and outer cone), in lux or candela; an `intensity` left null is its type's default |
| `Camera3D`, `OrbitCamera3D` | A camera with a `Projection`; an orbiting one that turns, zooms and damps |
| `Decal3D`, `Mirror3D`, `ReflectionProbe3D`, `Particles3D` | A projected decal, a planar mirror, a reflection probe, a particle system |
| `Binding3D` | Nodes for the simulation's components, through the scene bindings plugins registered |
| `Contributor3D` | A `PassContributor` drawing into the scene pass |

Every spatial widget extends `Spatial3D` (`position`, `rotation`, `scale`,
`visible`, `children`). A root-level widget's `position`, and a camera's
`target` wherever it hangs, is a place in the world: each build converts it
through `Scene.toScene`, so a rebuild after the view shifted the origin
leaves the node where it stood; below another widget `position` is the
parent's space. A tap hands a `Tap3D`, the hit (a `HitResult` of its own)
with the pointer. A model that will not load goes to `onError` and
`errorBuilder`, or to the view's `EngineLog` with neither, never to the
zone. `SceneWidgets.mount` mounts the same widgets into a `Scene` with no
view, for a test or a tool.

```dart
Widget teapotScene() => Scene3D(
  view: const ViewSettings(
    settings: RenderSettings(bloom: BloomSettings(intensity: 0.08)),
  ),
  children: <Widget>[
    Camera3D(position: Vector3(0, 1.5, 4), target: Vector3.zero()),
    const Light3D.sun(),
    Model3D(
      source: 'assets/models/teapot.glb',
      onLoaded: (ModelInstance teapot) => teapot.player?.playNamed('idle'),
    ),
    Mesh3D(
      shape: const SphereShape(radius: 0.25),
      position: Vector3(1.2, 0.25, 0),
      material: RenderMaterial(
        baseColor: LinearColor.fromSrgb(0.9, 0.4, 0.3),
        roughness: 0.4,
      ),
    ),
  ],
);
```

### `SceneSurface`, the lower layer

`SceneSurface` is the widget that hands a frame to Flutter, with nothing
around it: no loop, no device opening, no fallback. It takes a `renderer`, a
`scene`, a `view` (`RenderView`), `settings` (a function called once per
frame, so anything derived from the camera is read after it moved),
`onBeforeFrame`, `presentFrame` (a `FramePresenter`), and optionally
`moreViews`, `onFrame`, `cadence` (`FrameCadence`) and `pixelRatio`.
`openDevice(width:, height:)` opens a device the same way the view does,
and `presentFrame` is the default presenter. Use it to embed the renderer in
a loop of your own (the Flame bridge does).

**What grows in 1.x.** New members of the settings groups, with defaults.
New scene widgets. New members of `Flutter3dEngine` and `EngineFrame`. The
callbacks keep their one-argument shape: an event a later minor says more
about gains a member on its event object.

## Scenes and nodes

The scene graph is in `flutter3d_core` and exported by `flutter3d`.

| Type | Key members |
|---|---|
| `Scene` | `root`, `add`, `remove`, `clear`; `meshes`, `lights`, `cameras`, `decals`, `probes`, `reflectors`, `lodGroups`; `ambientColor`, `ambientIntensity` (lux), `environment`; `origin`, `toScene(WorldPosition)`, `toWorld(Vector3)`, `shiftOrigin`, `onOriginShift`, `rebaseAround`; `computeBounds` |
| `SceneNode` (`base`) | `name`, `parent`, `children`, `add`, `remove`, `removeFromParent`; `setPosition`, `setRotation`, `setRotationYawPitchRoll`, `setScale`, `setLocalMatrix`, `lookAt`, `setLocalForward`; `localMatrix`, `worldMatrix`, `worldPosition`; `isVisible`, `layerMask`, `lightChannels`; `onAttachedToScene`, `onDetachedFromScene` |
| `MeshNode` (`base`) | `mesh` (`MeshGeometry`), `material` (`RenderMaterial`), `parameters`, `skeleton`, `morph`, `tint`, `outlineColor`, `frustumCulled`, `castsShadow`, `worldBounds` |
| `InstancedMeshNode`, `LodGroup`, `ImpostorNode`, `LineStripNode` | Many copies in one draw, switching by screen coverage, a camera-facing card, a polyline |
| `CameraNode` | `projection` (`PerspectiveProjection`, `OrthographicProjection`, `OffAxisProjection`, `TiledProjection`), `viewMatrix`, `viewProjection(aspect)` |
| `LightNode` | See [lights and cameras](#lights-and-cameras) |
| `DecalNode`, `PlanarReflectorNode`, `ReflectionProbeNode` | Projected decals, mirrors, cube captures |
| `Shape` and its kinds | `SphereShape`, `CuboidShape`, `CylinderShape`, `ConeShape`, `TorusShape`, `CapsuleShape`, `DiscShape`, `PlaneShape`, `LatheShape`: values that build `MeshData` |
| `MeshData`, `MeshBuilder`, `DeviceMesh` | CPU geometry, a builder, and geometry uploaded to a device (`DeviceMesh.upload`) |
| `Raycaster`, `HitResult`, `Renderer.pickPixel` | Picking by ray and by the object-id pass; a `HitResult` is new per cast and its fields are final |

Positions in a node are scene space: float32, relative to `Scene.origin`.
A place in the world is a `WorldPosition` (doubles) and crosses into scene
space through `Scene.toScene`. The three spaces are in
[the units contract](../../docs/CONTRACTS.md#three-spaces).

```dart
Scene lit() => Scene()
  ..add(LightNode(intensity: 100000.0)..setLocalForward(Vector3(-0.4, -1, -0.3)))
  ..add(
    LightNode.lumens(1200.0, range: 8.0, name: 'bulb')
      ..setPosition(0.0, 2.5, 0.0),
  );
```

**What grows in 1.x.** New node kinds and new members on `Scene` and the
nodes. `SceneNode` and `MeshNode` are `base`: a subclass written outside
keeps compiling, and a member added later arrives with a body.

## Assets, formats and loading

### Formats

Every JSON file the engine writes starts with the envelope `format`,
`version`, `requires`, `generator`; a binary format carries its own magic
and version. A 1.x engine reads every 1.x file, lifting older versions
through a chain of migrations, and refuses a newer one with a sentence that
names both versions. Unknown keys are kept. The rules are in
[the envelope](../../docs/CONTRACTS.md#the-envelope).

| Format | Files | Package | Versions read | Loaded by |
|---|---|---|---|---|
| glTF 2.0, GLB | `.gltf`, `.glb` | `flutter3d_core` | glTF 2.0 with its common extensions | `loadModelByPath`, `GltfLoader`, `decodeModel` |
| OBJ, STL, FBX, USDZ, splats | `.obj`, `.stl`, `.fbx`, `.usdz`, `.ply`, `.spz` | `flutter3d_core` | | the same decoders; FBX is refused with a reason, USDZ is written only |
| `f3d.model` | `.f3d` | `flutter3d_core` | 1 to 2 | `F3dDecoder`; the build converts sources into it |
| `f3d.materialLanguage` | `.f3dmat` | `flutter3d_core` | 1 to 3 | the build, or `RuntimeShaders` at run time |
| `f3d.fmat` | `.fmat` | `flutter3d_core` | 1 | `loadMaterial`, `readFmat` |
| `f3d.level` | `.level.json` | `flutter3d_sim` | 1 to 5 | `Level`, `LevelLoader` |
| `f3d.run` | `.f3drun` | `flutter3d_sim` | 1 to 5 | `Demo` |
| `f3d.inputTape` | `.tape.json` | `flutter3d_sim` | 1 to 2 | `InputTape` |
| `f3d.save` | `.save.json` | `flutter3d_sim` | 1 | `Snapshot` |
| `f3d.effect` | `.f3dfx` | `flutter3d_particles` | 1 to 2 | the particle effects |
| `f3d.plugin` | `.f3dplugin` | `flutter3d_plugin_runtime` | 1 to 4 | `DataPluginLoader` |
| `f3d.physicalMaterial` | `.material.json` | `flutter3d_matter` | 1 to 2 | `PhysicalMaterial` |
| `f3d.settings`, `f3d.actions` | `.settings.json`, `.actions.json` | `flutter3d_game` | 1 to 2, 1 | `SettingsFile`, `ActionMap` |

The full table, with every format and what `migrate --data` does with
each, is in the [migration guide](https://flutter3d.pleion.dev/reference/migrating-to-1.0/#data-files).
`FormatSpec` declares a format (id, suffixes, version, migrations,
fixtures), and `coreFormats`, `simFormats` and `gameFormats` are the
engine's lists.

### Loading models

| Call | What it does |
|---|---|
| `loadModelByPath(path, {bundleSource, decoders, deviceClass, read})` | A `ModelDocument` from a path: a bundle asset, a file, or a `scheme:` source a plugin registered |
| `loadModelAsset(sourcePath, {..., read})` | The build's converted copy of a source under `assets_src/` (`.f3d`, per device class), falling back to the source in a debug build |
| `ModelAsset.fromDocument(document, {device, lighting})` | Uploads a document: `parts`, `nodes`, `skins`, `clips`, `materials`, `variants`, `localBounds`; `dispose()` |
| `ModelAsset.instantiate(scene)`, `instantiateFitted(scene, length:)` | A `ModelInstance` in a scene: `root`, `meshes`, `skeletons`, `player` (`AnimationPlayer`), `selectVariant`, `removeFromScene`, `adopt` |
| `ModelWardrobe<K>` | Models looked up by key and dressed onto visuals |
| `LevelLoader.load(assetPath, {device, registry, read})` | A `LoadedLevel`: `scene`, `collision` (`CollisionWorld`), `issues`, `probes`, `decals`, `cull(eye)`, `dispose(device)`; `read` hears every file it reads and stops at the next one when canceled |
| `loadMaterial`, `bindMaterial`, `loadMaterialDocument` | A `RenderMaterial` from a material file or a `MaterialDocument` |

```dart
Future<ModelInstance> place(GraphicsDevice device, Scene scene) async {
  final document = await loadModelByPath('assets/models/teapot.glb');
  final asset = await ModelAsset.fromDocument(document, device: device);
  return asset.instantiateFitted(scene, length: 1.0, onGround: true);
}
```

`AssetSource` (`key`, `read(AssetRead)`, `resolveUri`) is where bytes come
from: `BundleAssetSource`, `FileAssetSource`, `HubAssetSource`, or one a
plugin registers under a scheme. An `AssetRead` is what a reader asks of
one read: `onProgress` (an `AssetProgress`: `received`, `total`,
`fraction`), `cancel` (an `AssetCancel`: `cancel()`, `isCanceled`,
`whenCanceled`, `throwIfCanceled`) and `range` (an `AssetByteRange`);
`AssetRead.whole` asks for nothing. A source that cannot report, stop or
read a range ignores it. The loaders take `read:` and read through
`AssetRead.readFrom`, which checks the signal around the call and reports
the whole file once it has arrived; a canceled load fails with
`ResourceLoadCanceledException`.

```dart
Future<ModelDocument> loadWithBar(
  void Function(double? fraction) shown,
  AssetCancel cancel,
) => loadModelAsset(
  'assets_src/robot.glb',
  read: AssetRead(
    onProgress: (AssetProgress p) => shown(p.fraction),
    cancel: cancel,
  ),
);
```

The schemes `http`, `https`, `file`, `asset`,
`data`, `blob`, `package`, `hub` and `f3d` are reserved
(`AssetSources.reservedSchemes`). The build pipeline (`flutter3d_build`,
`flutter3d_assets.yaml`) is described in
[the asset pipeline](https://flutter3d.pleion.dev/reference/asset-pipeline/).

### Levels and tapes

A level is a document (`Level`, `f3d.level`) of brushes, lights, entities
and a `world` block; `LevelValidator` reports problems with their
coordinates. An entity's `type` is an `EntityKind` from an `EntityKinds`
registry, which a plugin can extend. A run is recorded as an `InputTape`
(the inputs, step by step) or a `Demo` (`.f3drun`: the level, the starting
`Snapshot`, the tape, checkpoints, the `SimulationVersion`, a `PoseRecord`
and probe readings). See [the simulation loop](#the-simulation-loop) for
replay.

**What grows in 1.x.** New formats, new versions of a format (read by
every later 1.x), new decoders and sources. A file a 1.x engine wrote opens
in every later 1.x. The meaning of an existing field in a format is frozen.

## Materials

| Type | What it is |
|---|---|
| `RenderMaterial` | What a mesh draws with: `lighting` (`LightingModel`), `baseColor` (`LinearColor`), `metallic`, `roughness`, the maps (`albedo`, `normal`, `metallicRoughness`, `occlusion`, `emissiveTexture`) and their samplers, `emissive` and `emissiveStrength` (nits), `alphaMode`, `alphaCutoff`, `blendMode`, `doubleSided`, `depthWrite`, `depthCompare`, `depthLayer`, `effectsDepth`, `parameters`, `extraTextures`, `physicalMaterial`; `copy()` |
| `LightingModel` | A lit or unlit stage: `unlit`, `lambert`, `blinnPhong`, `pbr`, `pbrLayered`, `toon`, `normals`, `xray`, and models from the material language; `LightingModels` registers more |
| `Material3D` | A `RenderMaterial` as a widget, shared by the meshes below it |
| `MaterialParameters` | The uniforms of a material's own block, by name: `operator []=`, `setNamed`, and typed through `ParameterKey<T>` (`set`, `valueOf`) with a `MaterialParameterSchema` |
| `MaterialDocument`, `SurfaceMaterial` | A material as a file describes it, before it meets a device |
| `BundledMaterials` | A compiled bundle's materials by name: `[name]` (the `LightingModel`), `parameters(name)` (the uniforms at their defaults), `state(name)` (the draw state the source declares), `schema(name)` |
| `PhysicalMaterial` | What a surface is made of, for physics, sound and heat, by id (`f3d.granite`); `RenderMaterial.physicalMaterial` names it |

A material with a stage of its own is written in the material language
(`.f3dmat`, versions 1 to 3); the build compiles it for every backend and
writes typed accessors for its uniforms into `lib/materials.g.dart`. The
language is described in
[the material language](https://flutter3d.pleion.dev/reference/material-language/),
and what a lit model of a plugin's own may declare is in
[the plugin API](../flutter3d_plugin_api/API.md#custom-materials-and-lit-models).
A `compute` stage of the language is a texture computed texel by texel:
`lowerMaterialCompute(program)` writes it in the kernel language
(`MaterialComputeKernel`: `kernel`, `load(device)`, `bake(width, height)`,
`parameterBytes`), which runs wherever a device computes. Impeller and
WebGL2 refuse it naming `DeviceFeature.compute`; there `bake` computes the
texture on the CPU at load.

```dart
const ParameterKey<LinearColor> tint = ParameterKey<LinearColor>(
  'tint',
  ParameterType.color,
);

void tintIt(RenderMaterial material) {
  material.parameters.set(tint, const LinearColor(1.0, 0.5, 0.2));
  material.emissiveStrength = 200.0; // nits
}
```

Physical materials live in the `MaterialCatalog` of `flutter3d_matter`,
`f3d.<name>` for the engine's own (`Materials`), each group of properties
in SI with its `source`. Two materials meeting take the geometric mean of
their friction and the larger restitution unless the catalogue has a
measured `MaterialPair`. See
[physical materials](../../docs/CONTRACTS.md#physical-materials).

**What grows in 1.x.** New lighting models, new members of
`RenderMaterial` with defaults that draw as before, new material language
versions (an older source keeps every name it had). A minor may change the
picture only with a CHANGELOG entry and a settings flag that brings the old
look back; a patch does not change it.

## Lights and cameras

| Type | Key members |
|---|---|
| `LightNode` | `type` (`LightType`), `color`, `intensity` (lux for a directional light, candela for the others), `range` (meters, 0 for unbounded), `innerConeAngle`, `outerConeAngle` (radians), `width`, `height` (an area light), `castsShadow`, `channels`; `LightNode.lumens(...)` converts lumens to candela once |
| `LightType` | `directional`, `point`, `spot`, `area`, and `LightType.custom(name, base:)` for a plugin's own |
| `Light3D` | The widget: `.sun()` (15 000 lux), `.directional()`, `.point()` and `.lamp()` (an 800-lumen bulb, about 63.7 cd), `.spot()` (`innerConeAngle`, `outerConeAngle`; 800 lumens poured into its cone by default); a plain `Light3D(type: …)` with no `intensity` takes its type's default in its type's unit |
| `CameraNode`, `Camera3D`, `OrbitCamera3D`, `OrbitController` | A camera, its widgets, and an orbiting controller |
| `PerspectiveProjection` | `fovY` (radians, the vertical angle), `near`, `far`; `.infinite()` |
| `PhysicalCamera`, `ThinLens` | Exposure and depth of field from aperture, shutter and sensor |
| `Atmosphere`, `PhysicalSky`, `SkySettings` | Sky, sun and ambient, photometric |
| `flutter3d_camera` | Virtual cameras (`VirtualCamera`, framings, blends, shakes) that the genres' cameras are presets of |

Light is photometric: a scene lit from a datasheet looks the same here.
Ambient light and a sky's sun are in lux, emissive surfaces in nits,
exposure in EV100. See [light](../../docs/CONTRACTS.md#light).

**What grows in 1.x.** New light types take codes below 16, which the lit
stages read; a plugin's take 16 and up. New projection kinds and camera
members. The light row a lit stage reads is frozen.

## Render settings and post effects

`RenderSettings` is one `const` value read every frame (by
`ViewSettings.settings`, or by `SceneSurface`'s function). Its groups:

| Field | Type | Area |
|---|---|---|
| `exposure`, `tonemap`, `tonemapCurve`, `outputTransform`, `autoExposure`, `localExposure`, `camera`, `physicalCamera` | | Exposure and the display transform |
| `shadows` | `ShadowSettings` | Directional cascades, point and spot shadows, soft shadows |
| `antiAlias`, `renderScale`, `spatialUpscale` | | Edge smoothing, temporal resolve, resolution |
| `bloom`, `depthOfField`, `motionBlur`, `lightShafts`, `volumetricFog`, `fog`, `sky` | | Lens and atmosphere |
| `ambientOcclusion`, `contactShadows`, `reflections`, `planarReflections`, `reflectionProbes`, `decals` | | Shading |
| `transparency`, `occlusion`, `clusteredLights`, `reversedDepth` | | How the frame is drawn |
| `debugView`, `viewportShading`, `highContrast`, `xray`, `debug` | | Debugging and accessibility |
| `frameWorkBudget` (`Duration`), `telemetry` | | Budgets and reporting |
| `stepsOff`, `extensions` | `Set<RenderStep>`, `SettingsExtensions` | Steps switched off; settings a plugin added |

`settings.without({RenderStep.bloom})` and `settings.only({...})` switch
whole steps; a step that needs a switched-off one goes with it, and
`FrameResult.skipped` names both. `RenderStep.values` lists the engine's
own steps (shadows, bloom, depth of field, motion blur, temporal
anti-aliasing and the rest).

```dart
const RenderSettings dusk = RenderSettings(
  exposure: 1.0,
  shadows: ShadowSettings(),
  ambientOcclusion: AmbientOcclusionSettings(enabled: true),
);
RenderSettings lean() => dusk.without(<RenderStep>{RenderStep.bloom});
```

The post-processing effects are plugins, in `flutter3d_post`: one library
per family (`light.dart`, `shading.dart`, `reflections.dart`,
`atmosphere.dart`, `motion.dart`, `style.dart`) and `standard.dart` with
all of them. Each is a `RenderStepAddon` (`BloomAddon`, `FogAddon`,
`TemporalAntiAliasingAddon` and the rest) or a `LightingModelAddon`
(`ToonLightingAddon`). Depending on the package installs them through
discovery, switched by what the settings say, so the frame does not change
until a setting does. A pubspec's `flutter3d_plugins:` block takes a family
or a class out (see [plugins](#plugins)).

`Renderer` is the object below it all: `Renderer.create(device:)`,
`render(...)`, `warmUp`, `warmUpInSlices`, `captureNextFrame`,
`pickPixel`, `memoryReport`, `describePipeline`, `renderSteps`
(`RendererSteps`), `hooks`, `lightTypes`, `lightingModels`,
`sceneBindings`, `listener` (`RenderListener`), `dispose()`.
`FrameResult` reports each frame's passes, skips and timings.

**What grows in 1.x.** New settings groups and fields with defaults that
leave the frame as it was, new steps and anchors. The anchors a plugin
places a pass at keep their order; the frame resources' encodings are
frozen.

## The simulation loop

The simulation (`flutter3d_sim`, plain Dart) steps at a fixed rate, in
ordered phases, and replays exactly from its inputs. A view runs one for
you; a server or a test makes one by hand.

### `EngineLoop`

| Member | What it does |
|---|---|
| `EngineLoop({input, world, timing, plugins, registries, materials, backend, profile, determinismCheck, catchUp, longestFrame, ...})` | Makes the loop and installs its plugins |
| `addSystem(name, phase, system, {after, before})` | A system (`LoopSystem`, handed a `LoopContext`) in a phase, ordered by name |
| `addPhase(phase, {after, before})`, `addAssimilation(...)` | A phase of your own; a stage that turns external readings into world state |
| `frame(dt)`, `frameAtVsync(vsync)` | One displayed frame: runs the steps the time source says are due, then the frame phases |
| `runSteps(count)` | Steps without a clock |
| `step`, `stepSeconds`, `alpha`, `timing`, `changeTiming`, `timeScale`, `isPaused`, `time` | Where the run is, and its clock |
| `events` (`EventBus`) | The bus: `declare`, `publish`, `onStep`, `onFrame` |
| `world` (`EcsWorld`), `queries` (`SimQueries`), `published` (`PublishedState`), `onPublished` | The state, questions asked of it, and what the view reads |
| `capture()`, `restore(snapshot)`, `digest()`, `keep(window:)`, `rewindTo(step)` | Snapshots, digests and rewinding |
| `recorders`, `playback` | Recording and replaying `InputTape`s |
| `onStepInput`, `onStepEnd`, `onChange`, `onOriginShift` | Observers, each handed one value |
| `origin`, `shiftOrigin`, `stageWorld`, `shiftsPhysics` | The floating origin and the collision world it moves |
| `plugins` (`PluginManager`), `simulationVersion`, `profile` | The plugins, and the version of the simulation the run is |

Step phases run in this order inside every step: `input`, `movers`,
`physics`, `fields`, `rules`, `publish` (`LoopPhase.stepPhases`). Frame
phases run once per displayed frame, after the steps: `animate`, `audio`,
`camera`, `render`, `ui`. A system reads `step`, `dt`, `isResimulated` and
`world` from its `LoopContext` and publishes events through it; it never
reads a clock.

```dart
int score = 0;

EngineLoop headless() {
  final input = InputState();
  final loop = EngineLoop(input: input, timing: const WorldTiming(stepRate: 60))
    ..addSystem('score', LoopPhase.rules, (step) {
      if (step.isResimulated) return;
      score += input.pressed(GameAction.jump) ? 1 : 0;
    });
  loop.time = ManualTime();
  return loop;
}
```

### Time

`WorldTiming(stepRate:)` is the step rate (60 by default,
`standardStepRate`); `stepSeconds` is the fixed `dt`. How many steps a frame
brings is the `TimeSource`'s answer, and it never changes `dt`:

| Source | Factory | Steps |
|---|---|---|
| real time | `TimeSource.realTime()` | Wall-clock time between frames (the view's default) |
| `DisplayTime` | `TimeSource.display()` | The display's clock, with a predicted present time (what `XrDriver` steps by) |
| scaled | `TimeSource.scaled(factor)` | Real time times a factor |
| `LogTime` | `TimeSource.log(timestamps)` | A log's timestamps |
| `ManualTime` | `TimeSource.manual()` | Only what `advance(seconds)` adds |

A frame that falls too far behind is cut at `longestFrame` and announced
as `TimeLost` on the bus, by the `CatchUp` policy.

### Profiles and placement

`SimulationProfile` says what the simulation promises:
`SimulationProfile.deterministic` (bit-exact, float32, fixed steps; the
default, and what games, tapes and matches use) or
`SimulationProfile.accurate` (double precision, adaptive steps, not
bit-exact). Code asks `isBitExact`, `usesDoublePrecision` and
`allowsAdaptiveSteps` rather than comparing names; a plugin may define a
profile of its own under its namespace.

`SimulationPlacement` (in `LoopSettings.simulation`) runs the simulation
`.inline()` in the view's isolate or `.isolate(factory)` in one of its own
(on the web, the same factory in this isolate). The view then talks to it
through a `SimulationHandle`: `submit(input)`, `published`,
`onPublished`, `ask(name)`, `query(question)`, `rewindTo(step)`,
`simulation`, `dispose()`.

### Probes and published state

A `Probe` (`id`, `quantity`, `unit`, `region`: `ProbeBody`, `ProbePoint`,
`ProbeSection`; or `derived` from other probes in the expression language)
is a component on an entity. The loop samples each one per step through
the `ProbeSampler` registered for its quantity and publishes a
`ProbeReading` (`probe`, `step`, `value`, `unit`, `kind`, `quality`).
`PublishedState.probe(id)` reads the latest, `ProbeBuilder` shows it in a
widget, and a `Demo` keeps the readings of the run it recorded.

### State from outside

A sensor's reading, a log line or a headset's pose enters as input:
`InputState.feedExternal(ExternalStateInput(...))` puts it on the next
live step and its tape. It carries `source`, `value`, `unit`,
`sourceTime`, `receivedTime`, `quality` (`ReadingQuality`), `kind`
(`ReadingKind`) and `tag`. While the input is muted (during a replay, a
scrub or a bisection) a reading is dropped. A source on its own clock
queues readings and drains them from `EngineLoop.onStepInput`.

```dart
void feed(InputState input, double celsius) => input.feedExternal(
  ExternalStateInput.quantity(
    'boiler.thermometer',
    Quantity(celsius, Unit.celsius),
    quality: ReadingQuality.good,
  ),
);
```

### Tapes, replay and rollback

| Type | What it is |
|---|---|
| `InputTape`, `InputTapeRecorder`, `InputTapePlayback` | Inputs per step, recorded and played back into an `InputState` |
| `Snapshot`, `Snapshots` | The whole state, `capture()` and `restore()`; `requires` names the plugins whose state it holds |
| `StateDigest`, `DigestTrace`, `EventTrace` | Digests per step and events per step, to say where two runs part |
| `Demo` | A recorded run (`.f3drun`); `refusalOn(running)` says why another simulation cannot play it |
| `SimulationVersion` | The engine number, the genre, every simulation plugin, subsystem and the profile; `refusalOn(running)` |
| `PoseRecord`, `PoseRecorder` | Body poses every few steps, written beside a tape; they always play, even where the tape is refused |
| `ReplaySide`, `TapeBisection` (`TapesAgree`, `TapesDiverge`) | Two runs stepped side by side, and the first step they part at |
| `RewindBuffer`, `RewindPoint` | Keyframes and input for the last seconds, for rewinding |
| `RunTimeline` (`flutter3d_game`) | Pause, scrub, branch, step and return to the present over a `RewindBuffer` |
| `DeterminismCheck`, `DeterminismError` | Each step run twice in a debug build, naming the system that differed |

```dart
void replay(EngineLoop loop, InputTape tape, Snapshot start) {
  loop.restore(start);
  loop.playback = InputTapePlayback(tape);
  loop.runSteps(tape.steps);
}
```

A step run again (a rollback, a scrub) is `isResimulated`; the frame
channel of the bus reconciles its events with what it already showed
instead of showing them twice. Rollback netcode for two peers is
`flutter3d_net` and `flame_multiplayer`; a match is formed only between
builds of the same `SimulationVersion`. Its step function
(`RollbackSession.applyAndStep`, `EngineRollback.applyFrames`) is handed a
`RollbackStep`: `step`, `frames` by slot, `statusOf(slot)` (an
`InputStatus`: `confirmed`, `predicted`, `disconnected`) and `resimulated`.

**What grows in 1.x.** New phases between the engine's (a plugin's are
namespaced), new time sources, new members of the loop and its contexts.
A patch never changes what the default simulation computes; a minor that
changes it moves the simulation version, and a tape from the older version
is refused with a reason while its `PoseRecord` still plays.

## Physics

| Type | What it is |
|---|---|
| `CollisionWorld` | Colliders, a broadphase, rays and sweeps that do not tunnel; `properties` (`WorldProperties`: gravity, air, wind, medium), `materials` (`MaterialCatalog`), `backend`, `origin`; `idOf(collider)` and `colliderOf(id)`, the ids a contact names |
| `Collider`, `CollisionShape` | `CollisionBox`, `CollisionSphere`, `CollisionCapsule`, `CollisionWedge`, `CollisionHeightfield`, `CustomShape` |
| `PhysicsBackend` | `DartPhysics` (the reference, plain Dart) or `NativePhysics` (`flutter3d_physics_native`, the C core, with joints, cloth, fluids and ragdolls); `dynamics(...)`, `cloth(...)`, `fluid` |
| `RigidDynamics`, `RigidBody` | Bodies with mass, friction (one μ), restitution and a `PhysicalMaterial`; `step(dt)`, `contacts`, `bodyOf(collider)`, `bodyOfId(id)` (a contact's id back to its body, on either core), `saveState`, `restoreState` |
| `CharacterController`, `MovementSettings` | A capsule that walks, steps and slides |
| `StepContact`, `ContactPhase` | One contact a step reported: bodies, point, normal, impulse (N·s), relative velocity, materials; `begin`, `persist`, `end` |
| `ContactEvent` (`flutter3d_sim`) | The same on the bus, `physics.contact`, step channel; its `bodyA` and `bodyB` are the world's ids, which `colliderOf` and `bodyOfId` read back |

Two bodies meeting take the geometric mean of their friction and the larger
restitution in both cores, and a scene 5 km out on a shifted origin stays
within the bounds in [the units contract](../../docs/CONTRACTS.md#space) in
both. A world's properties
are part of the simulation: a rewind restores the world a snapshot was
taken under.

```dart
void physics(EngineLoop loop) {
  final world = CollisionWorld();
  final dynamics = Dynamics(world: world);
  final crate = dynamics.add(
    RigidBody(
      world: world,
      shape: CollisionBox(Vector3.all(0.5)),
      position: Vector3(0, 2, 0),
      mass: 12.0,
    ),
  );
  loop
    ..stageWorld(world)
    ..addSystem('physics', LoopPhase.physics, (step) => dynamics.step(step.dt));
  loop.events.onStep<ContactEvent>('contacts', (delivered) {
    final contact = delivered.event;
    if (contact.phase == ContactPhase.begin && contact.impulse > 5.0) {
      // a hard landing: newton-seconds; dynamics.bodyOfId(contact.bodyB)
      // is the body that landed
    }
  });
}
```

**What grows in 1.x.** New shapes, new backend capabilities as mixins with
defaults (`JointPhysics`, `ConstraintPhysics`, `ShapePhysics`), new
contact phases (`ContactPhase` is an open set: a `switch` over it ends with
a wildcard). `PhysicsBackend` and `RigidDynamics` may be implemented
outside; their new members arrive with bodies.

## Input and actions

| Type | Package | What it is |
|---|---|---|
| `InputState` | `flutter3d_sim` | What the step reads: `pressed`, `held`, `released`, `axis`, `dualAxis`, `valueOf`, `moveAxis`, `lookDelta`, `feedExternal` |
| `GameAction`, `AxisAction`, `DualAxisAction`, `ActionSet` | `flutter3d_sim` | Named actions, open sets a game extends |
| `ActionMap`, `ActionBinding`, `InputSource`, `Bindings` | `flutter3d_game` | Which source drives which action (`f3d.actions` file), rebinding with conflicts |
| `DesktopInput`, `PadInput`, `ActionInput` | `flutter3d_game` | Keyboard and mouse, gamepads, and any source routed through a map |
| `PadDevice`, `PadReading`, `GamePadButton`, `GamePadAxis`, `MouseCapture` | `flutter3d_game` | Devices behind the game's own types; `.platform()` opens the real one |
| `XrControl`, `XrHand` | `flutter3d_sim` | XR controllers as input sources |

Buttons are named by physical position (`face.south`), so a saved binding
reads the same on any pad. The touch controls and the rebinding list are
widgets in `flutter3d_game_ui`.

```dart
ActionMap controls() => DesktopInput.defaultActionMap();
```

**What grows in 1.x.** New sources, actions and devices; `ActionKind`,
`GamePadButton` and `InputSource` are open.

## Audio

`flutter3d_audio_core` (plain Dart) is the mixer and the spatializer;
`flutter3d_audio` plays it through SoLoud (`SoLoudBackend`), and
`SilentBackend` plays nothing on a machine with no device.

| Type | What it is |
|---|---|
| `AudioScene` | `play(sound, at)`, `attach(sound, pose)`, `update(listener)`, `preload`, `maxVoices`, `occlusion`, `world` (the speed of sound comes from its air) |
| `AudioListener`, `AudioEmitter` | The ear and a playing sound: gain, pan, muffle, rate, following a `PoseSource` |
| `SoundDef`, `SoundBank`, `AudioBus`, `Mixer`, `DuckRule` | A sound, a bank of them, buses and ducking |
| `AudioBackend` | What a platform implements: `open`, `preload`, `start`, `update`, `stop` |
| `SoundOcclusion` (`flutter3d_game`) | The walls between a sound and the ear |

`Flutter3dView.onListenerMoved` hands the camera's pose as a
`ListenerPose` each frame.

**What grows in 1.x.** New backends and effects; `AudioBackend` is
implementable outside, and its new members arrive with bodies.

## XR

The XR contract is in `flutter3d_app`. A runtime (OpenXR, WebXR, a
platform's own) implements `XrSession`; the view drives it through an
`XrDriver` when `Flutter3dView.xr` is set.

| Type | What it is |
|---|---|
| `XrSession` (`abstract base`) | `start(request)`, `waitFrame()`, `endFrame(end)`, `end()`, `capabilities`, `state`, `states`, `createSwapchain`, `placeAnchor`, `restoreAnchor`, `vibrate`, `refusal(capability)` |
| `XrSettings` | `session`, `request` (`XrSessionRequest`: `mode`, `space`, `required`, `optional`), `panels`, `actions`, `swapchain`, `near`, `far`, `mainLight` |
| `XrCapability` | Open: `immersiveVr`, `immersiveAr`, `inline`, `hands`, `eyeGaze`, `anchors`, `planes`, `sceneMesh`, `depthOcclusion`, `lightEstimation`, `passthrough`, `haptics`, `quadLayers`, `cylinderLayers` |
| `XrFrame` | `views`, `poses`, `inputs`, `planes`, `meshes`, `light`, `depth`; `toInputs()` turns it into `ExternalStateInput`s |
| `XrLayer` | `XrProjectionLayer`, `XrQuadLayer`, `XrCylinderLayer`; `XrPanel` draws a widget on one |
| `XrAnchor`, `XrSpace`, `XrSessionState` | Anchors with an optional `GeoOrigin`, reference spaces, the session's states |

Poses enter the simulation as external state through the `XrPoses`
assimilation, so a recorded XR session replays. A capability a runtime
lacks is refused with an `UnsupportedCapabilityException`.
`package:flutter3d_app/xr_testing.dart` has `FakeXrSession` for tests.

**What grows in 1.x.** New capabilities, layers and frame members.
`XrSession` gains members only with bodies.

## Tools for editors and agents

The engine's editors are libraries first, so an agent edits through the
same commands a person does.

| Package | What it offers |
|---|---|
| `flutter3d_editor_core` | The level editor without a window: `Editing`, `EditorHistory`, `EditorCommand`, `EditorPieces` |
| `flutter3d_model_core` | The model editor's project, commands and history |
| `flutter3d_mcp` | MCP servers over stdio: `dart run flutter3d_mcp:editor_mcp` (`flutter3d.editor`), `:model_mcp` (`flutter3d.model`), `:project_mcp` (`flutter3d.project`); `kit.dart` is what they share (`ToolSpec`, `ToolCall`, `ToolResult`, `ToolTableServer`) |
| `flutter3d_sim_mcp` | `SimMcpServer` (`flutter3d.sim`): play a level headless; `DiagnosticMcpServer` (`flutter3d.diagnostics`): why a frame is wrong |
| `flutter3d_build` | The `flutter3d` command line and `plugin_mcp` (`flutter3d.plugins`) |
| VM service extensions | `ext.flutter3d.*` in a running game (`flutter3d_game`, `flutter3d_app`), `ext.flutter3d.version` announcing the schema |

Each server announces its schema version, and its tools, input and output
schemas are snapshotted in `api/*.mcp`; the VM extensions in `api/*.vm`;
the command line's subcommands, flags and exit codes (0 ok, 1 failed, 2
usage, 3 refused or out of date, 4 would overwrite) in
`packages/flutter3d_build/api/flutter3d_build.cli`. A plugin adds tools
under its namespace (see
[the plugin API](../flutter3d_plugin_api/API.md#the-editor-and-mcp-tools)).

**What grows in 1.x.** New tools and optional arguments. A renamed tool
keeps its old name as an alias until the next major.

## Plugins

Everything outside the engine's kernel installs as a plugin: the genres,
the post effects, the elements, and whatever somebody else writes. An
application hands plugins to `Flutter3dView` through
`PluginSettings(plugins: ...)`, or lets the build discover them:
`flutter3d_build` writes `lib/plugins.g.dart` with `installedPlugins`, a
`PluginGroup` of every plugin its dependencies mark, adjusted by the
pubspec's `flutter3d_plugins:` block (`without`, `set`, `with`). A plugin
is switched on and off at a step boundary (`EngineLoop.plugins.enable`,
`disable`), and the switch is journalled so a replay makes it at the same
step.

The contract a plugin is written against, every registry and hook, the
data and Wasm plugins and what an outside plugin may do are in
[`flutter3d_plugin_api/API.md`](../flutter3d_plugin_api/API.md). The
site's [plugin catalogue](https://flutter3d.pleion.dev/reference/plugins/)
lists published ones.

## Errors and refusals

Every exception the engine throws for a caller to handle is a
`Flutter3dException` (`message`, `cause`), in one of four families:

| Family | Means | Examples |
|---|---|---|
| `Flutter3dFormatException` (also a `FormatException`) | Bytes or text that cannot be read: a file, a document, a source | `GltfFormatException`, `F3dFormatException`, `LevelFormatException`, `MaterialSyntaxException` (line and column), `DataPluginFormatException`, `ReplayException`, `SnapshotFormatException`, `UnitMismatchException` |
| `ResourceException` | Something outside the program: a missing asset, a device, a store, a process | `AssetNotFoundException`, `StorageException`, `DeviceResourceException`, `DeviceUnavailableException`, `PipelineRefusedException`, `ShaderBundleException` (`stale` for a bundle to rebuild) |
| `CapabilityException` | What this device, backend or profile cannot do | `UnsupportedCapabilityException` (`feature`, `backend`, `reason`), `ComputePlacementException`, `FieldResidenceException`, `SimulationCapabilityException`, `RuntimeShadersException` |
| `PluginException` | A plugin that cannot install or did what it may not | `ConstraintCycleException`, `PermissionException`, `WasmException`, `WasmTrapException`, `UnknownMaterialException`, `FormatRegistrationException` |

`ArgumentError`, `StateError` and `AssertionError` mean a programming
mistake and are not part of the families. Two `Error`s are thrown on
purpose: `DeterminismError` (a step that ran differently twice) and
`FrameGraphError` (a frame graph that cannot be built).

```dart
Future<void> guarded(GraphicsDevice device) async {
  try {
    await loadModelByPath('assets/models/broken.glb');
  } on Flutter3dFormatException catch (error) {
    debugPrint('the file is wrong: ${error.message}');
  } on ResourceException catch (error) {
    debugPrint('the file is missing or a device refused: ${error.message}');
  } on CapabilityException catch (error) {
    debugPrint('this device cannot: ${error.message}');
  }
}
```

**Typed refusals.** Where saying no is a normal answer, the API returns it
instead of throwing. A `refusalOf(...)` or `refusalOn(...)` method answers
a sentence or `null` (`PluginApiVersion.refusalOn`,
`SimulationVersion.refusalOn`, `Demo.refusalOn`, `FieldHint.refusalOf`,
`PluginGrants.refusalOf`); a result type carries a refusal as one of its
cases (`ScrubAnswer`'s `ScrubRefused`, `ServiceAnswer`'s
`ServiceRefused`, `SaveUpgrade`'s `SaveRefused`); and the frame reports
what it declined (`FrameResult.skipped` with a `PassSkip` reason,
`FramePipelineRefused`, `RuntimeShaders.statuses`). A reason set
(`PassSkip`, `FieldRefusal`, `ComputeRefusalReason`,
`PipelineRefusalReason`) is open: a `switch` over it ends with a wildcard.

**What grows in 1.x.** New exception types inside the four families, and
new reasons. An exception never moves to another family within 1.x.

## Lifecycle and disposal

- **One owner disposes once.** A handle a `GraphicsDevice` made has one
  owner, who calls `dispose()` once; a second call asserts in a debug
  build, and the device's own `dispose` ends every handle it made.
- **The view disposes what it made.** `Flutter3dView` opens the device and
  makes the renderer unless `DeviceSettings` lends them; `ownsDevice` and
  `ownsRenderer` say which, and a borrowed one is the lender's to dispose.
- **Things a caller loaded are the caller's.** `ModelAsset.dispose()`,
  `LoadedLevel.dispose(device)`, `Renderer.dispose()`,
  `SceneWidgetsMount.dispose()`, `SharedMeshes.dispose()`. A mesh or
  texture still in a frame in flight is released with
  `Renderer.releaseMeshAfterFrame` and `releaseTextureAfterFrame`.
- **A registration is cancelled, not disposed.** Every `add`, `register`
  and `on…` that returns a `Registration` is undone with `cancel()`; a
  plugin's registrations are cancelled for it when it is switched off.
- **`dispose` ends, `close` disconnects, `stop` pauses.** `close()` is for
  a connection or a stream; a `stop()` beside `dispose()` is a state change
  that `start()` may follow.
- **A lost device is reported.** `DeviceSettings.onDeviceLost`
  (`DeviceLostEvent`) and `onDeviceRestored`; `Flutter3dEngine.loss`.

## Units

Meters, seconds, kilograms, radians; Y up, right-handed, a camera looking
down negative Z; colors linear unless the name says sRGB; lights in lux and
candela, emissive in nits, exposure in EV100; world positions as
`WorldPosition` doubles. A member whose unit is not the contract's says so
in its name. The whole contract is [`docs/CONTRACTS.md`](../../docs/CONTRACTS.md):
[space](../../docs/CONTRACTS.md#space), [time](../../docs/CONTRACTS.md#time),
[mass and force](../../docs/CONTRACTS.md#mass-and-force),
[color](../../docs/CONTRACTS.md#colour), [light](../../docs/CONTRACTS.md#light),
[files](../../docs/CONTRACTS.md#files) and
[names](../../docs/CONTRACTS.md#names). `Quantity` and `Unit` (in
`flutter3d_foundation`) carry a number with its unit where one crosses a
boundary: probes, external readings, field declarations.

**Frozen at 1.0.** The units, the axes and the spaces.

## Versioning, stability and migration

**Strict semver from 1.0.0.** A patch fixes and adds nothing that breaks; a
minor adds; a break waits for a major, after a deprecation that names its
versions and its replacement and lasts at least six months. Every public
name of every published package is in its `api/<package>.api` snapshot,
and the structure check fails a change that does not match its version
bump. There is no experimental corner. The policy in full is in
[SUPPORT.md](../../SUPPORT.md#versions) and
[the API is a snapshot](../../CONTRIBUTING.md#the-api-is-a-snapshot).

**One major.minor, patches per package.** The engine's packages share a
major and a minor and move together at a minor or a major; a patch goes
only to the package that needs it, so `flutter3d_impeller` may be at 1.0.1
beside the rest at 1.0.0. `pad_input` and `flutter3d_pointer_lock` keep
their own lines below 1.0. The plugin API has a number of its own
(`PluginApiVersion`), and so does the Wasm plugin ABI.

**What a minor can add, and what it cannot.** A minor adds types, members
of `final` and `base` classes, optional parameters, settings fields,
formats and format versions, tools, phases, anchors, and values of the open
sets. It cannot change the shape of a type an application touches, add a
required member to an interface implemented outside, change the default
simulation, change what a field of a format means, or add a value to a
closed `enum` or `sealed` type.

**The open-class rule.** A set that may grow (a kind, a reason, a phase, a
backend, a format) is a `final class` with `static const` members, `values`,
`name` and `byName`, never an `enum`; a result that may gain a case is an
`abstract final` class. A `switch` over one ends with a wildcard that
refuses or names the value. The few `enum`s and `sealed` types left are
closed for good, each with the reason in its doc.

**Outside semver.** The libraries named `internal.dart` and `builtin.dart`
(in `flutter3d_foundation`, `flutter3d_shaders` and `flutter3d_cpu`) are
for the engine's own packages, which ask for each other within one minor;
a minor may change them. An application does not import them.

**Implementable interfaces.** Outside code may implement the HAL
(`GraphicsDevice`), physics backends, audio backends, decoders and writers,
network transports, storage (`Storage`, `BinaryStorage`), XR sessions and
plugins. These are `abstract base` classes, and a member added in a minor
arrives with a body. A member they declare never gains a parameter within
a major; where an input will grow, it arrives as a descriptor field (a
pipeline's next input is a `PipelineDescriptor` field, read by
`GraphicsDevice.createPipelineFrom`).

### Migrating from 0.8

```bash
dart pub global activate flutter3d_build 1.0.0-rc.1
dart pub global activate flutter3d_lints 1.0.0-rc.1
dart pub global run flutter3d_build:migrate --dry-run .
dart pub global run flutter3d_build:migrate .
```

`flutter3d migrate` moves the constraints to `^1.0.0-rc.1`, rewrites the
imports of libraries that moved, runs `dart fix` with the fix data every
package ships, applies the rewrites that need resolved code through the
`flutter3d_lints` plugin, and prints a report; each change it leaves to you
has a `// TODO(flutter3d-1.0):` in the code with a link. `--data` lifts
data files to their current versions (`--backup` keeps the old ones). The
0.8 to 1.0 table, `flutter3d_build/lib/migrations/0.8_to_1.0.yaml`, has
2062 entries, 308 of them by hand; the site's
[migration guide](https://flutter3d.pleion.dev/reference/migrating-to-1.0/)
lists every one by package. The largest shape change is `GameLoop` to
`EngineLoop`:

```dart fragment
// 0.8
final loop = GameLoop(input: input, onStep: (dt) => world.step(dt));
loop.advance(dt);
```

```dart
// 1.0
final loop = EngineLoop(input: input)
  ..addSystem('world', LoopPhase.physics, (step) => world.step(step.dt));
loop.frame(dt);
```

After 1.0, each later release gets a table of its own, and `migrate`
applies every table after the release a project's `pubspec.lock`
resolves.
