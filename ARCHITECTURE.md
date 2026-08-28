# flutter3d — architecture

**An independent implementation of a real-time 3D engine for Flutter**, written
in this repository from the geometry layer up. It is not a fork, a binding or a
wrapper around another engine, and it is not affiliated with the Flutter team.

This document states how the system is put together and why each part has the
shape it does. It is the single design reference for the repository; READMEs say
what a package is *for*, and this says how the pieces fit.

Flutter 3.47.0 stable, Dart 3.12.2. Where a fact depends on the SDK version, the
version is named.

---

## Contents

1. [What the engine is](#1-what-the-engine-is)
2. [The constraints that shape the design](#2-the-constraints-that-shape-the-design)
3. [The package map](#3-the-package-map)
4. [Rendering](#4-rendering)
5. [Scene and camera](#5-scene-and-camera)
6. [Materials, shaders and lighting](#6-materials-shaders-and-lighting)
7. [The backend contract](#7-the-backend-contract)
8. [Assets and formats](#8-assets-and-formats)
9. [The simulation layer](#9-the-simulation-layer)
10. [Physics](#10-physics)
11. [Input, audio and UI](#11-input-audio-and-ui)
12. [Extension points](#12-extension-points)
13. [How correctness is held](#13-how-correctness-is-held)
14. [Performance characteristics](#14-performance-characteristics)
15. [Limits](#15-limits)
16. [Distribution](#16-distribution)

---

## 1. What the engine is

A real-time 3D engine on Flutter GPU, a game layer on top of it, and three games
built from both. It exists to build 3D games and interactive 3D applications in
Dart from one codebase, on desktop and on the web.

Three properties govern every decision below:

- **Abstraction over the graphics API.** Three independent backends implement one
  interface, and user code names none of them.
- **A deterministic simulation.** The same start fed the same intents reaches the
  same place, exactly.
- **Game code separated from the subsystems.** The simulation does not know how a
  frame is drawn.

**Target platforms**, stated as a table because "should work" was doing too much
work in the sentence this replaces:

| | Draws | Gamepad | Pointer capture | Built here |
|---|---|---|---|---|
| macOS | yes, Impeller | yes | yes | every commit, and the golden sets |
| Web | yes, WebGL2 | yes | yes | every commit, `--wasm` |
| Android | yes, Impeller | yes | n/a | builds; never run on a handset |
| iOS | yes, Impeller | yes | n/a | simulator only |
| Windows | untried | **no** | **no** | no runner directory exists |
| Linux | untried | **no** | **no** | no runner directory exists |

**"Desktop" in this repository means macOS.** Neither `pad_input` nor
`pointer_lock` has a Windows or Linux native side — both answer `isSupported`
false there, honestly and by design, so nothing crashes — and no application
has a `windows/` or `linux/` directory to build in the first place. A
first-person game on either would be played by dragging the mouse, with no
controller. The Dart halves that carry every trap are written and tested; what
is missing is XInput plus `ClipCursor`, and evdev plus XI2 raw motion.

Android and iOS build and none has been played on a handset — what a phone
alone can answer is whether the on-screen stick is the right size, whether the
buttons are reachable, whether there is enough screen left to turn the camera,
and whether the device holds a frame.

**Flutter GPU is a per-application setting on every platform, and it fails
silently.** Apple platforms want `FLTEnableFlutterGPU` in `Info.plist`; Android
wants `io.flutter.embedding.android.EnableFlutterGPU` in the manifest, which the
engine reads with a default of false. An application that has not set it fails to
initialise the shader library and draws nothing, with nothing in the log naming
the cause — which is why a scan checks every application against every platform
it has ([§13](#13-how-correctness-is-held)). Two games had already shipped
Android builds without it.

`FLTEnableImpeller` is set beside it: Flutter GPU requires Impeller, which is not
the default renderer on macOS, and a default is a thing that can change.

**Dependencies are close to none.** The render core, the physics, the game layer,
the software rasteriser and the particle system are written here. External:
`vector_math`, an audio backend, the Flutter SDK, and `flutter_bloc` in
`flutter3d_ui` and two applications. That is not an end in itself: there is no
Dart equivalent of Jolt, assimp or miniaudio, and an FFI wrapper breaks the web.
The price is that all of this code is tested here
([§13](#13-how-correctness-is-held)). Licences are MIT/BSD/Apache/zlib; no GPL.

---

## 2. The constraints that shape the design

These are properties of the channel, verified by reading the Dart that ships
inside the SDK rather than inferred from documentation. Most of the architecture
follows from them.

**Shaders are compiled ahead of time into a bundle.** There is no runtime
compilation, so a material graph cannot be assembled while the game runs. The
engine uses **AOT permutations: one shader per lighting model**. The bundle format
is tied to the SDK version, so it is rebuilt whenever Flutter moves — a structure
scan compares the bundle's timestamp against its sources.

**Compute passes are not exposed.** Compute exists in Impeller, and `impellerc`
accepts `--input-type=comp`, but the Dart API does not surface it. So GPU
particles, GPU skinning, GPU culling, indirect draw and GPU sorting of transparent
objects are unavailable; all of that runs on the CPU.

**Reflection cannot answer "bind or not".** A shader that *declares* a uniform
block but reads nothing from it still reports the block at a non-zero size, while
the compiled Metal function has no buffer for it. Binding such a phantom block is
a `SIGSEGV` inside `setFragmentBuffer:offset:atIndex:` with no Dart stack trace,
and a `sizeInBytes == null || == 0` check does not prevent it. The engine
therefore carries its own permutation metadata — the `usesFragInfo`,
`usesMaterialMaps`, `usesEnvironment` flags on `LightingModel` — and
`tool/build_shaders.sh` prints the compiled binding table after every build so the
hand-written metadata cannot drift from it unnoticed. The same applies to
samplers: one the shader never reads is dropped from the signature.

**Uniform blocks are reflected by struct type name, textures by variable name.**
For `uniform FrameInfo { … } frame_info;` the key is `FrameInfo`; for
`uniform sampler2D base_color_texture;` it is the variable. Unused members of a
block disappear from reflection, so writing code tolerates missing members.

**Arrays in a uniform block work.** `vec4 lights[8]` survives into the compiled
struct at the std140 size, with the member after the array at the right offset.
Individual elements are not reflected, so the array is written as one contiguous
block from its base offset — correct, because the std140 stride for a `vec4` array
is a flat 16 bytes. This is what the lighting design rests on.

**One render pass per command buffer.** Metal allows a single encoder open at a
time and flutter_gpu offers no way to end a pass; a second pass on the same buffer
aborts the process. A multi-pass frame is therefore a command buffer per pass,
submitted in order — buffers on one queue execute in submission order, so pass
ordering comes for free.

**`CommandBuffer.submit()` is asynchronous.** Resetting a host buffer immediately
after submitting rewinds a bump allocator the GPU is still reading. The engine
keeps a ring of host buffers sized by the frames in flight, which is three.

**A pass's clear covers the whole attachment**, whatever the viewport says, while
`setViewport` and `setScissor` are pass *state* and take effect part way through.
Together those two facts are what make an atlas affordable: six cube-shadow faces
are six viewport changes and six draws inside **one** pass that clears once, not
six passes.

**Dart has a GC.** Every `Vector3` is a heap object, so hot paths use pooled
temporaries, `Float32List` storage, in-place `Matrix4` operations and `out`
parameters. GC jank eats the frame budget faster than draw calls do.

**`sampleCount` is 1 or 4.** `StorageMode.deviceTransient` is tile memory: a
direct saving for MSAA and depth attachments, and such textures cannot be bound to
a shader. `Texture.asImage()` goes from a GPU texture to a `ui.Image` with no CPU
copy, and is the bridge into the widget tree.

---

## 3. The package map

Twenty-three packages and five applications in one pub workspace — one
`flutter pub get` for the repository.

### 3.1 The layering rule

> **`flutter3d_game` does not depend on `flutter3d`.** The simulation, the input
> and the collisions know nothing about how a frame is drawn.

Everything else follows from it. The things that break quietly — a collision
passing through a wall once in a thousand steps, a jump of different heights on
different monitors, a keypress eaten at a low frame rate — are reachable from an
ordinary unit test, and none of the three is visible in a screenshot.

`flutter3d_bridge` is the only package allowed to depend on both sides.
`flutter3d_physics` is pure Dart with no Flutter, so its tests run under
`dart test`.

### 3.2 The packages

| Package | Owns |
|---|---|
| `flutter3d_hardware` | The graphics vocabulary a backend implements: devices, encoders, handles, formats. Names no graphics API |
| `flutter3d_impeller` | The backend over `flutter_gpu`, and the compiled shader bundle |
| `flutter3d_webgl` | The WebGL2 backend, and GLSL translated from `flutter3d_shaders` |
| `flutter3d_cpu` | A software rasteriser: a second reference, and rendering with no GPU |
| `flutter3d_backend` | Picks a backend for a build — conditional import plus `openDevice` |
| `flutter3d_conformance` | The contract suite every backend passes |
| `flutter3d_shaders` | The GLSL both hardware backends compile, and the list of required entry points |
| `flutter3d` | The engine: scene graph, render list, passes, materials, assets, animation |
| `flutter3d_samples` | The Khronos test models the decoders are checked against and the demo browses. Fixtures, so that a game depending on the engine does not carry them |
| `flutter3d_particles` | CPU emitters and the particle pass contributor |
| `flutter3d_physics` | Collision world, character controller, rigid bodies, spatial grid |
| `flutter3d_game` | The genre-neutral game layer: fixed step, input, level format, actors, ECS, snapshots |
| `flutter3d_game_shooter` | Shooter rules: weapons, hitscan, projectiles, inventory, monsters |
| `flutter3d_game_platformer` | Platformer rules: runner, coins, hazards, checkpoints |
| `flutter3d_game_racing` | Racing rules: cars, circuits, laps, ghosts |
| `flutter3d_bridge` | Simulation state to scene: actor visuals, fixture visuals, particle effects |
| `flutter3d_audio` | Loading, streaming, 3D positioning, voice limits, mix buses |
| `flutter3d_ui` | Screens that are not the game: menus, settings, rebinding, storage |
| `flutter3d_session` | The run lifecycle that ties a game, a device and a screen together |
| `flutter3d_app` | The assembly layer, as one import |
| `flutter3d_testing` | Rendering a scene with no GPU and comparing it against a reference image |
| `pad_input` | Gamepad devices on web, Android, macOS and iOS |
| `pointer_lock` | Relative mouse movement: a method channel on macOS, the Pointer Lock API in a browser, which Flutter surfaces on neither |

Applications: `apps/flutter3d_demo_dungeon` (shooter),
`apps/flutter3d_demo_platformer`, `apps/flutter3d_demo_racing`,
`apps/flutter3d_editor` (level editor), plus the engine's own example.

### 3.3 Rules that are scanned, not remembered

`tool/structure.dart` walks `packages/` and `apps/` and enforces twenty-one rules in
under a second, as the first step of CI. They cover the *arrangement* of the code
— who imports what, what a name says, where a thing may live — while anything
about what the code *does* stays a test.

The load-bearing ones:

- **No package names a genre.** Not just imports: a dictionary of forbidden words
  catches `CollisionLayers.monster`, which imports nothing. Words of *fiction* and
  of *one genre's repertoire* are forbidden; mechanisms are not, which keeps the
  list small — `pickup`, `sprint`, `jump`, `platform` and `coyote` are all allowed,
  because each names what a thing does rather than what kind of game it is in. The
  detector splits identifiers on `_` and camelCase humps and compares whole words,
  so `currentLap` fires and `overlaps` does not, and it strips comments, because a
  detector that fires on prose gets deleted.
- **A genre package reaches no other genre**, and **no package depends on an
  application**.
- **The engine names no backend**, and **the hardware layer names no graphics
  API**.
- **A step reaches for no clock and no loose dice** — the scan behind
  [§9.3](#93-determinism).
- **The compiled shader bundle is not older than its sources.**
- **Documents agree with the tree**: the test count, the rule count and the
  publishing order are each compared against what is actually there.

The detectors prove they fire before a single file is scanned, and a broken
detector stops the run: a green scan behind a broken detector is worse than a red
one, because people believe it.

---

## 4. Rendering

### 4.1 The frame

```
for each RenderView in ascending priority:
  1. aspect from the viewport → projection matrix
  2. view = camera.node.worldMatrix.inverted()   (cached by worldVersion)
  3. extract the frustum
  4. a linear pass over the scene's renderable registry:
       visible? layer mask matched? world sphere inside the frustum? → DrawItem
  5. compute packed keys, sort indices
  6. walk the sorted order: bindPipeline only on a change, uniforms per draw
  7. present
```

No tree traversal and no allocation in steps 4–6.

A frame runs its passes in order — shadows, sky, scene, post — each in its own
command buffer, because [§2](#2-the-constraints-that-shape-the-design) allows one
pass per buffer. `FrameGraph` compiles the pass list and its resources;
`FrameResources` owns render targets and releases them by identity after the
frames in flight have passed.

### 4.2 The render list and packed sort keys

```
stateThenDepth: [ bucket:8 | pipeline:6 | material:15 | depth:14 ]  → ascending
backToFront:    [ bucket:8 |            invDepth:35            ]  → farthest first
```

The pipeline is the high-order field because shaders are compiled ahead of time:
switching a pipeline inside a pass is the most expensive state change there is, so
sorting by it is structural rather than an optimisation.

**The budget is 43 bits, not 64**, and this table said otherwise for a long
time — twelve bits of pipeline, twenty of material and twenty-four of depth,
which is a scene an order of magnitude larger than the one the code sorts.
Twenty bits are reserved for the draw index the key carries as its payload
(`kPayloadBits`), and what is left is above. Two consequences worth stating
rather than discovering: opaque depth **saturates past 256 units**, so two
objects further out than that sort by material instead of by distance; and
material ids wrap at 32 767, past which two materials can share one and the
sort quietly gets worse. Neither is a correctness bug — a wrong order costs
overdraw, not a wrong picture — and both are numbers somebody sizing a scene
against this document would otherwise get wrong by a factor of ten.

The transparent key carries no pipeline field at all: back-to-front is the
whole of what correctness requires there, and spending bits on state would take
them from the depth that decides whether the picture is right.

Sorting is a radix sort over packed keys (`sortPackedKeys`), with an ordinary sort
below a threshold of 96 entries, where eight passes clearing a 256-entry histogram
would cost more than they save.

Sort modes are a **setting** on the view rather than a policy welded into the
renderer: `stateThenDepth`, `backToFront`, `frontToBack`, `manual`, `none`.

### 4.3 Passes

**Shadows.** A directional light's shadow pass is a render view whose camera is
the light, with an orthographic volume fitted to the scene. Depth goes into a
**colour** target, because a depth texture cannot be sampled through flutter_gpu,
and the orthographic camera is what makes `gl_FragCoord.z` a linear distance worth
comparing. Front-face culling, PCF 3×3, a depth bias and a normal offset.

**Three cascades, side by side in one atlas.** §15 said for a long time that a
single map was all the directional light had, and that had stopped being true:
`ShadowSettings.cascades` defaults to 3, split logarithmically at
`cascadeSplit` 0.7 over a `viewDistance` of sixty metres. Each cascade fits a
sphere along the view axis and is texel-snapped to its own grid, so the shadow
does not swim as the camera moves; the shader is handed the far and farthest
matrices beside the near one and picks by depth.

The cost is the honest reason to keep the number small: the atlas is
`resolution` × `cascades` wide, so a 2048 map at three cascades is 6144 texels
across. That is the same arithmetic that made a cube tile expensive before it
got its own `cubeResolution` — one number multiplied by a count nobody was
looking at.

Point lights use cube shadows in an atlas. Faces store radial distance rather than
depth, because depth is per-face and would seam at every boundary; the shader is
handed the same six matrices that drew them, so there is no second derivation to
disagree. A light keeps two atlases — one for what moves and one for what does not
— and the shader takes the nearest occluder from both; the static half is rendered
once at load, since a dungeon's walls do not move.

**The static half is redrawn when the rows change hands, when the texture is
reallocated, and when a setting the pass reads changes** — the last of those was
missing, and its absence was a setting that could not be changed at all. Drawing
the crypt twice with opposite `casterFaces` produced two frames identical to the
pixel; the atlas simply kept what the first bake put in it. `StaticBakeKey` names
what the *pass* reads — which side of a caster is recorded, the volume's padding,
the tile size — and deliberately excludes everything the *lookup* reads, since
baking again for a bias would redraw six views of the level per occupied row to
produce the pixels already there.

**A cube face has its own resolution, and that is what paid for the sixth row.**
The atlas is six tiles across and one row per shadowed light, so deriving a cube
tile from the cascade's `resolution` — which is what it did — meant a game asking
for a 1024 sun got 6144 texels across per atlas, 201 MB at four rows, and there
are two of them. Four hundred megabytes of video memory, on a platform where a
browser tab has less. `cubeResolution` defaults to 512, which is about a
centimetre per texel two metres from a torch — finer than the penumbra it is
sampled through — and the golden sets did not move when it changed.

**A normal offset is in texels.** What it clears is the width of one texel of
the map out where the fragment is — the texel records its whole patch of surface
at one distance, and everything else in that patch compares against a distance
measured somewhere it is not. That width is a solid angle and grows with range,
so an offset fixed in metres is right at one distance and wrong at every other:
2 cm was enough beside a lamp and a third of what a floor ten metres out needed,
which showed as that floor shadowing itself across everything the light reached,
stopping dead in a straight line where the floor's own edge projects into the
atlas. Straight edges in a shadow are worth suspecting for this reason — nothing
in a scene of curved surfaces makes one, but the boundary of what a shadow map
contains does.

**Six lights cast at once rather than four**, which is the crypt's own number:
it hangs six torches, and at four rows two of them lit their corner and cast
nothing, with *which* two changing as the player walked. Two torches side by side
behaving differently is what a player reads as broken shadows, and they are right.
Six rows at the tile above is 75 MB against 50; at the tile it inherited before,
the same step would have been 302.

**HDR and composite.** The scene renders into `r16g16b16a16Float`. Tone mapping
(Khronos PBR Neutral), exposure and the sRGB encode happen in a composite pass,
which is what lets anything above display white survive long enough for
post-processing to see it. Bloom is a threshold with a soft knee, a chain of
half-size targets down and a tent filter back up. `LookSettings` adds colour
grading, vignette, grain and chromatic aberration in the same pass; the software
backend mirrors all of it, so the two references can be compared exactly.

**Contributors.** A pass can be extended without editing the renderer:
`PassContributor` receives a `PassEncoder` — the recording half of the interface,
with no `submit` — so a contributor cannot end somebody else's pass. Particles are
the first user.

### 4.4 Culling and level of detail

Frustum culling runs over a flat registry of renderables, with world bounds cached
by `worldVersion`. A median-split BVH over world bounding spheres backs both
culling and raycasting, and is rebuilt only when a transform version changes.

The BVH is not unconditionally better, and the numbers say when: with 200,000
objects and everything on screen the tree *loses* — 4.6 ms against 2.4 ms linear —
because it can reject nothing, while with the world larger than the view it wins
outright. A rebuild of that scene costs 93 ms, so a large scene that moves every
frame belongs on the linear path.

`LodGroup` switches by the fraction of the viewport an object's bounding sphere
covers, not by distance: the same object at the same distance is worth different
detail through different lenses. Selection happens once per view, before the
render list is built, because the choice changes which nodes are visible. Hidden
levels fall out of culling and picking for free.

`LodGroup.forMaterials` builds a group from one mesh and several materials, so a
distant object samples a smaller *texture*. It is per object rather than per
pixel, so a floor running to the horizon still aliases, but it covers the common
case of a prop holding a four-thousand-pixel texture while occupying thirty pixels
of screen.

---

## 5. Scene and camera

### 5.1 A tree with flat registries

`MeshNode`, `CameraNode` and `LightNode` extend `SceneNode`, which stays narrow:
transform, hierarchy, visibility, layer mask. Inheritance does not oblige a
per-frame tree walk — `Scene` maintains flat registries on attach/detach, so
culling is a linear pass over a contiguous list while `traverse` remains for user
code. That keeps both a familiar API and the property Dart's GC requires.

### 5.2 Versions instead of dirty flags

A node has `_localVersion` and a remembered `_seenParentVersion`. The
`worldMatrix` getter compares the parent's version against the remembered one and
recomputes on a mismatch, recursing upwards.

- No separate update pass exists, and none is needed: a stale transform is
  structurally impossible, so the classic missed-`updateMatrixWorld` frame of
  latency cannot happen.
- Changing a node does not require walking its subtree, unlike a push-down flag.
- A query is O(depth) worst case and O(1) normally.
- `worldVersion` gives free invalidation of everything derived: world bounds, the
  view matrix, the inverse matrix for normals.

The version counter is global on purpose. A per-node counter would let reparenting
between nodes with matching numbers go unnoticed.

### 5.3 The camera

`Projection` is sealed — `PerspectiveProjection`, `OrthographicProjection` — and
the view matrix is the node's inverted world matrix, cached by `worldVersion`.
Because the camera is a node it parents like anything else: a camera in a cockpit
is a child node, and controllers drive **a node** rather than a camera, which is
why one orbit controller can also swing a light around a model.

The `[0, 1]` depth convention lives in exactly one place,
`PerspectiveProjection.toMatrix`, with unit tests pinning it. A swapped element in
the depth row of a projection matrix is a black viewport with no error anywhere,
and it is caught with no GPU — which is the argument for keeping the camera and
the maths in a layer that does not depend on flutter_gpu.

### 5.4 RenderView

A `RenderView` carries a camera, a normalised viewport fraction, a layer mask, a
priority, clear settings and a target spec. That gives split-screen, a mini-map,
rendering into a texture and shadow passes from one abstraction: a light's camera
is also a `RenderView`.

Layers are a bitmask on the node plus a mask on the view, with the
opaque/transparent split derived from the material's alpha mode.

### 5.5 Asset versus instance

`ModelAsset` holds meshes, materials and textures uploaded to the GPU — immutable,
reusable, cached. `asset.instantiate(scene, parent)` builds nodes and attachments,
so one model can stand in the scene as many times as wanted, sharing meshes and
textures.

`instantiate` rebuilds the decoded hierarchy rather than flattening it, because an
animation track says "move node 7" and node 7 has to carry its subtree.

### 5.6 Shapes are values

Geometry generators are polymorphic types rather than static methods: `Shape` with
`CuboidShape`, `SphereShape`, `LatheShape` and the rest, where surfaces of
revolution derive from `LatheShape` — sphere, cylinder, cone, torus, capsule, disc
and an arbitrary profile. A shape can be stored, passed and replaced with your own
implementation. The same pattern applies elsewhere: the depth convention is a
method on `Projection`, glTF component rules belong to `GltfComponentType`, and
pixel generation is `ProceduralTexture`.

`CuboidShape` is not `BoxShape` because `flutter/material.dart` exports its own,
and the clash would force every application to resolve an import conflict.

---

## 6. Materials, shaders and lighting

### 6.1 Lighting models

Six ship: Unlit, Lambert, Blinn-Phong, PBR (GGX), Toon and Normals. Each is a
separate pre-built fragment shader, so switching models switches pipeline — which
is why the renderer caches pipelines by shader name and sorts by it.

`LightingModel` is a **value class, not an enum**, so the list is not closed: an
application that builds its own bundle can add an entry and the renderer caches a
pipeline for it like any other. What it cannot do is add a shader to a bundle it
does not build.

Its `uses…` flags are **declared rather than detected**, for the reflection reason
in [§2](#2-the-constraints-that-shape-the-design). `pipelineGroup` is an FNV-1a
fold of the shader name rather than `hashCode`, because Dart does not promise a
string's hash is stable between runs and the draw sort uses it — a
nondeterministic sort shows up as goldens differing by a quarter of their pixels.

### 6.2 Material inputs

Metal-rough, glTF-compatible: base colour, metallic, roughness, normal (with a
full TBN), ORM, occlusion and emissive, plus alpha masking and vertex colours.
**Neutral fallback textures instead of per-map flags**, so the shader needs no
branch and the engine no bookkeeping; the alpha cutoff is a negative sentinel when
the material is not masked, so masking needs neither a flag nor a permutation.

Tangents are generated with Lengyel's method where a mesh has none and taken
analytically where the surface knows them.

A material also carries `parameterBlock`, `parameters` and `extraTextures` — the
uniform block and slots an application's own shader reads. Nothing the engine
ships uses them; they are what makes a custom shader usable without editing the
renderer.

### 6.3 Lights

Directional, point and spot, with glTF's inverse-square falloff, range window and
smooth cone ramp. Up to eight are packed into `vec4[8]` uniform arrays with the
count as a uniform, so switching a light on or off never rebuilds a pipeline.
Intensities are unitless multipliers rather than lumens.

Image-based lighting is a prefiltered specular chain plus a diffuse level, built
by `EnvironmentMap.prefilter` from a cube map or from sky settings. The
convolution walks a fixed golden-angle spiral with no randomness in it, which is
what lets two independently written backends agree exactly.

---

## 7. The backend contract

`flutter3d_hardware` is the interface a backend implements and the engine draws
through. Three implement it: `flutter3d_impeller` over `flutter_gpu`,
`flutter3d_webgl` over WebGL2, and `flutter3d_cpu`, a software rasteriser with no
GPU, no driver and no shading language under it.

The third is not a toy. It gives a second, independently written reference set of
golden images, and it is what lets rendering run in CI with no graphics card.
Agreement between two independent implementations is evidence; agreement of one
with itself is a tautology.

`flutter3d_backend` chooses one for a build through a conditional import on
`dart.library.js_interop`. It is a separate package rather than part of the
session layer, because sessions would then depend on every backend, and the editor
— which has no web build — would pull WebGL in transitively.

### 7.1 What is promised

Changing any of these breaks a backend, and that is the bar for changing them.

- **`GraphicsDevice` — every member.** What formats it prefers, what it can do,
  how a pass is opened, how geometry and textures arrive, how a finished frame
  reaches the screen.
- **`CommandEncoder` and `PassEncoder`.** The split is deliberate: `PassEncoder`
  is the recording half without `submit`, so handing a contributor an
  already-submitted pass is a type error rather than a comment warning about one.
- **`RenderPassDescriptor`, `ColorTarget`, `DepthTarget`, `ScreenRect`,
  `BlendState`.**
- **Handles** — `TextureHandle`, `GeometryBuffer`, `ShaderHandle`,
  `PipelineHandle`, `ShaderLibrary`. A handle carries a description and an opaque
  backend object. `TextureHandle` deliberately has no `==`: the pool lends by
  identity and the frame releases by identity, and value equality would break both.
- **The sixteen enums in `formats.dart`**, plus `SamplerOptions`,
  `RenderTargetSpec`, `TextureAllocator` and `RenderTargetPool`. Their value names
  are load-bearing beyond the package: the Impeller translation asserts each maps
  to the flutter_gpu value of the *same name*, which catches a mapping that swapped
  two entries.
- **`PassState` and the `setState` extension**, which no backend implements
  anything for. `setState` is statically dispatched over `PassEncoder` and built
  only from types already listed, so a backend gets it free and cannot get it
  wrong. It exists for a Vulkan-shaped backend that must accumulate rasteriser
  state and look a pipeline up at `draw()`, and needs something hashable to
  accumulate into. Its fields are optional as a semantic, not a convenience: unset
  means *emit nothing*, because what an omitted call means differs per backend.

### 7.2 Semantics a signature cannot show

A backend that gets one of these wrong compiles and draws the wrong thing.

- **A clear covers the whole attachment**, whatever the viewport or scissor say.
  GL does not give this for free — `clearBufferfv` respects `SCISSOR_TEST`.
- **Rectangles are stated from the top left**, matching where row zero of a render
  target is. A backend whose framebuffer origin is at the bottom flips them; the
  engine will not.
- **`readPixels` returns rows from the top**, independently and for the same
  reason: a caller cannot tell which way round it was handed pixels, and a golden
  compared against a mirrored frame fails as though rendering broke.
- **A sampler a shader declares must be bound.** Leaving one unbound is a native
  crash with no Dart frame on at least one backend, so the engine binds a stand-in
  rather than nothing.
- **`bindUniformBlock` returns false for a block the shader does not have**, which
  is ordinary — a compiler drops a block nothing reads. A block that exists
  *without* a member the caller named is an error: the two ends then disagree about
  its shape, and zeros are a plausible-looking value for most of what goes through
  there.
- **A null `sampler` means `SamplerOptions.linearRepeat`**, not the constructor's
  own defaults, which are nearest and clamp. Taking the constructor defaults draws
  hard seams where the other backends draw soft ones — about two percent of every
  textured golden, looking exactly like a filtering bug.
- **`GeometryUsage` is not a hint.** WebGL binds a buffer to its target for life,
  and a buffer uploaded as vertices can never be bound as indices; the attempt is
  an `INVALID_OPERATION`, the draw is dropped, and the frame comes back the clear
  colour with nothing logged.
- **A pass leaves the vertex attributes it enabled switched on**, and a backend
  built on a context rather than a command buffer has to put them back itself.
  This is context state: it outlives the encoder, the pass and the frame. A stage
  with more attributes than the next one leaves the extras on with no buffer under
  them, which in WebGL2 is another `INVALID_OPERATION` and another dropped draw.
  The sky found it — eight attributes against a mesh's five and a post stage's
  none — and the symptom was not a missing sky but an entirely black frame,
  because the composite that puts the picture on screen was one of the draws
  being dropped. A shader that declares its attribute locations rather than
  leaving them to the linker is the other half: an interleaved vertex written in
  one order and read back in whatever order reflection happened to return is a
  layout nobody stated.
- **`setDepthWrite(false)` means depth writes are off**, on all three backends,
  since SDK 3.47. Before that flutter_gpu's native setter ignored its argument, and
  the software backend mirrored the bug deliberately: an honest implementation put
  the particle scenes five to ten percent away from the hardware one, and a gap
  that size is loud enough to hide a real regression behind. The rule outlives the
  bug — **when a backend must choose between being right and being comparable,
  comparable wins**, and the choice earns a test that fails the day it stops being
  necessary.
- **Ask before requesting what a backend may not have** — `supportsWireframe`,
  `supportsOffscreenMsaa`, `depthRange`, `framebufferOrigin`, `hdrColorFormat`,
  `preferredSampleCount`, `supportsMipmaps`. A backend refuses loudly rather than
  substituting something that looks similar.

**Outside the promise**, because nothing beyond the package should depend on it:
everything in `flutter3d`'s `src/` past what `flutter3d.dart` exports;
`FrameResources` internals; and the compiled bundle's format and location, which
is one backend's build output.

### 7.3 What the interface cannot abstract

**Shader names.** The engine asks for entry points — `MeshVertex`, `Pbr`,
`Composite` — and for uniform blocks and members by name, and every backend ships
a bundle answering to them. `flutter3d_shaders` holds the GLSL and
`kRequiredShaders` the names, pinned to the build manifest by a test, which makes
that one list rather than three. A backend can be written against the interface;
its bundle must be written against the GLSL.

Member names are the sharp edge and fail silently in both directions: a shader
asking for a member nobody wrote gets zeros, and a caller naming a member the
block lacks is an error.

This is also the limit on extensions. An application that builds its own bundle
can add a lighting model, because `LightingModel` is a value class. One that does
not control the bundle cannot.

### 7.4 Two rules a fragment stage keeps

**A fragment stage declares exactly the outputs its target has.** The scene pass
carries one colour attachment when nothing reads the surface buffer and two when
something does. Declaring the wrong number kills the process inside Metal, and
when it survives long enough to draw, every uniform the stage reads is rubbish.
Nothing above the driver reports anything.

**A uniform block reaches every pipeline except the sky's, on Impeller.** Bound
with the same call every mesh and post stage uses, in the same pass, with
reflection reporting the right size and offsets, the sky's blocks never arrive.
The sky is therefore fed through vertex attributes and the varyings built from
them. This is measured off recorded frames rather than assumed.

### 7.5 Conformance

`flutter3d_conformance` is the suite every backend passes, split in two tiers.
`coreChecks` covers clears, uploads and readback — everything a new backend can
ask before its first compiled shader — and `shaderChecks` is the rest. The split
matters because a backend that believed a suite claiming to need no shaders would
meet failures it could do nothing about.

The suite runs headless against the software backend, and
`packages/flutter3d_impeller/tool/conformance.sh` runs it on a live GPU and
returns an exit code.

---

## 8. Assets and formats

### 8.1 Model decoding

glTF 2.0 / GLB, Wavefront OBJ and the engine's own `.f3d` all produce one
`ModelDocument` — surfaces, `SurfaceMaterial`s, `EncodedImage`s, a node hierarchy,
skins, animations and `warnings`. That is what makes `ModelAsset.fromDocument()`
the single upload path, with mesh and image deduplication written once.

The glTF layer depends on neither flutter_gpu, `dart:io` nor `dart:ui`: external
files arrive through an `AssetUriResolver` callback and images are handed back
still encoded. That is what makes it testable with no GPU and no Flutter binding,
and usable from an isolate.

Materials are normalised to metal-rough, because that is what glTF defines and
what the shaders implement. OBJ predates PBR, so its parameters are **explicitly
approximated** — `Kd` becomes base colour, the Phong exponent `Ns` becomes
roughness — and the approximation is documented where it happens rather than
hidden. Non-fatal problems land in `warnings` and are surfaced rather than logged,
so a skipped primitive or an ignored extension explains a model that looks odd but
still loaded.

Decoding runs on a background isolate. File reads stay on the UI isolate and
sibling files are requested back over a port. This does not make decoding faster;
it removes the jank, and no native code would help — a native call from the UI
isolate blocks it exactly the same way.

### 8.2 `.f3d`

The engine's own container, written by hand rather than with flatbuffers: the
schema is small and fixed, and a dependency would buy nothing a section directory
does not. Vertex and index arrays are stored exactly as `MeshData` holds them, so
loading builds typed-data views over the file rather than copies — every blob
entry is 4-byte aligned precisely so those views are legal. A reader skips a
section kind it does not know.

The reason it exists is measured: the same teapot takes **4.54 ms as OBJ against
1.1 µs as `.f3d`**, and the two render pixel for pixel identically. That is about
360×, and it is a property of the format rather than of the parser — one is binary,
the other is text split by a regular expression and run through `double.tryParse`.

### 8.3 `.fmat`

A material is a file, not part of a model. A look — a studio's brushed steel, the
water on level three — is authored once and worn by many meshes, and glTF cannot
say that: it writes the material into every file that uses it, so changing the
steel means re-exporting every model made of it.

`.fmat` is text JSON, because it is a few hundred bytes an artist edits between two
runs of the game and that should be visible in a diff. Inside is a
`SurfaceMaterial` — the same vocabulary every model decoder produces — plus the
three things a material inside a model cannot have: images by path, the
application's own shader, and the parameters that shader reads.

The shader is named by a `LightingModel` rather than by a string, because the name
is only half the contract: the flags say what the compiled shader actually binds,
and the flag defaults fall the safe way.

Texture paths are interned into an indexed list at decode time, so a consumer
uploads images without knowing which format they came from and an image used by two
slots is uploaded once.

### 8.4 Textures and caching

PNG and JPEG through `dart:ui`, uploaded as RGBA8 — there are no compressed pixel
formats in use, so a 2048² texture costs 16 MB regardless of how small its file
was. Mip chains are built on the CPU by `MipChain.build` and every backend uploads
the same bytes, because WebGL2 has `glGenerateMipmap`, Impeller has nothing of the
kind, and a chain generated per backend is two of them agreeing by accident. Ask
`supportsMipmaps` first: a hand-built chain samples as **black** on OpenGL ES 2
without `GL_APPLE_texture_max_level`.

A chain is not a memory saving — it costs a third more — it is an aliasing fix.

`ResourceCache` reference-counts loaded assets. Loading is asynchronous; there are
no priorities and no cancellation.

### 8.5 Levels and saves

The level format is versioned JSON, validated before a run, and refuses to read
documents from the future. The validator reports a specific problem with a
coordinate — `LevelIssue(severity, message, where)` — rather than "the file is
broken". Rules about a level *as a whole*, such as "exactly one start", belong to a
particular game rather than to the format, so the game passes them in as a list.
The package contains no monsters, no weapons and no furniture, and holds no opinion
about whether the game has any.

**A snapshot is one mechanism, not three.** A save, a replication packet and the
input to a determinism test are the same state snapshot in three uses; keeping
three separate mechanisms correct costs three times as much as one. The format is
versioned with the same refusal to read the future, and the level format's tests
carry over unchanged.

A save is the level *and* the snapshot together. A snapshot stores metres, and
another level's metres are arithmetically meaningful and physically meaningless —
restoring one into the wrong level puts the player inside a wall — so `SaveFile`
refuses to hand out a snapshot without a level name.

---

## 9. The simulation layer

### 9.1 The loop

A fixed step for the simulation, a variable one for rendering, and interpolation at
draw time (`InterpolatedVector3`, `InterpolatedAngle`).

`GameLoop` owns three decisions that have no other home:

- look input is not consumed if no step ran this frame, or mouse movement is lost
  on a fast monitor;
- look input is divided evenly between the N steps of a frame, or the camera
  stutters;
- `beginStep`/`endStep` bracket every step, so a latch fires exactly once — without
  it one click is three shots.

Pause stops the clock rather than accumulating time it later throws away.

### 9.2 Step order

`WorldStep` holds the order the world is stepped in, as **named phases the game
calls** rather than one `run(dt)`:

**Movers first**, so a crate falling onto a lift that moved this step lands on
where the lift is now. **`reindex` before the bodies** — recorded as an argument
rather than a measurement, and no test pretends otherwise. **`clearKinematicDeltas`
after the bodies**, which is tested: a platform moving *sideways* carries its
passenger only through the delta, and clearing it early leaves the player standing
while the floor departs. **`update` before `publish`**: overlaps dispatch inside
`update` and report through flags, and `publish` is what asks the machinery what it
did — without it every consequence read out of those events silently never happens
while the world goes on changing. A step that reaches the end without publishing
trips a debug assert.

The phases are named and the game calls them in order because the constraint is not
the class's to settle: the platformer steps its actors **before** `reindex`, so the
index catches them and a sweep does not find a patrol in last step's place; the
shooter steps its actors **after everything**, so a monster reacts to where the
player just got to. Both are good arguments, and a single `run` would have picked
one silently.

### 9.3 Determinism

No step reaches for the system clock, and no step takes randomness from anywhere
but an explicitly passed `GameRandom` — a generator whose state is a number that
can be written down and restored. The generator is a required parameter with no
default, because a documented trap is still a trap and what makes this one
avoidable is that there is no way not to notice it.

Three things hold the rule, and none does another's work:

- **the scan** — "a step reaches for no clock and no loose dice" in
  `tool/structure.dart`. It fails on the *next* `Random()` or `DateTime.now()` at
  the moment it is written and names the file; it cannot say whether a simulation
  actually diverges;
- **behavioural tests** — each game's own, because the step belongs to the game;
  they will not say where the leak is;
- **`determinism_test.dart`** — about what the first two stand on.

Determinism here is for reproducible tests, replays and bug investigation, **not
for network synchronisation**. Floating point in the Dart VM and in a browser build
need not agree bit for bit, and rigid-body dynamics diverge from the last bit
within seconds, so deterministic lockstep over the web is a promise nobody could
keep. The networking model is client–server with an authoritative server and
snapshots.

### 9.4 Replays

`InputTape` stores a seed and one entry per fixed step. An entry holds
**transitions** — what was pressed and what was released — plus the axes and
analogue readings, which transitions cannot express and are therefore written every
step. The tape's size is proportional to what the player did, not to how long they
played.

It is a tape of intents, not of poses. The racing game's ghost is the second kind
and is right to be, since it survives the simulation changing underneath it; a tape
of intents does not survive that and must not — one that still arrived at the same
place after the physics changed would be a recording of nothing.

One tape covers three things: a replay at a few bytes a second; a bug that happens
once in a thousand steps, reproduced from a file attached to a report; and a test
that plays a whole level and asserts where it ended.

### 9.5 Entities

An ECS carries entity state: creation and destruction, components added at run
time, queries by component set. The transform hierarchy stays in the scene graph.

**Every component is serialisable**, and that is the condition the ECS exists for
rather than a feature beside it: a world snapshot, delta compression and
client-side correction all need the state enumerable in one place rather than
spread across lists the systems own.

### 9.6 Events

There is no event bus. A shared bus recreates at the subsystem level the mistake an
untyped "who is this" field makes at the object level: the sender does not know the
receiver, the type is lost, and debugging becomes a hunt for a subscriber.

Instead there are **typed per-step lists**, cleared at the top of `step`:
`ActorSystem.died`, `hurtThisStep`, `ProjectileSystem.detonations`,
`MechanismWorld.events`. Lists rather than streams because of the fixed step — a
stream delivers an event *after* the step that produced it, which is exactly the
property the package exists to provide. A list is synchronous, typed and allocates
nothing.

### 9.7 Level logic is data

There is no embedded scripting language. In AOT Dart an interpreter means FFI,
which breaks the web — the one platform this stack was chosen for.

The same property arrives by another means: level logic is expressed as data.
Mechanisms — doors, lifts, buttons, triggers — compose through signals, and the
format is versioned and validated before the run. What is lost is hot reload of
gameplay logic without a rebuild, partly compensated by Flutter's own hot reload.

---

## 10. Physics

`flutter3d_physics` is pure Dart with no Flutter dependency.

**Shapes:** box, sphere, capsule. Raycast, shape cast and overlap queries, filtered
by layers and masks. Convex hulls and triangle meshes are absent.

**The character controller is capsule-based and kinematic**, with steps, sliding
and coyote time. It is deliberately not rewritten as a rigid body: a player driven
by forces is a player who slides, and every shooter and platformer that feels good
drives its character kinematically and meets the dynamics through explicit
impulses.

**Rigid bodies** carry mass, gravity, impulses, pushing, rest and sleep, without
rotation. Angular momentum, inertia and joints are absent; when they arrive the
route is a **port** of a solver rather than a binding, because a port is readable
and keeps the web.

The reason there is a solver here at all rather than a dependency is not solver
quality but the **second world**. Every Dart physics library brings its own world,
shapes and broadphase, while the character controller, the doors, the navigation
bake and the snapshot all live in `CollisionWorld`. Two worlds obliged to agree
about where the walls are is exactly the class of failure this repository removes
systematically. An FFI binding to a mature C solver would break the web.

**Layers live in the game package, not the physics one.** A collision world that
knows what a monster is cannot be given to a game that has none. Physics holds the
rule — two colliders meet when each is in the other's mask — plus `Layers.all`, and
the game supplies the names.

---

## 11. Input, audio and UI

### 11.1 Input

`InputState` does not know where an action came from. Actions are logical, with
latches and axes; `Bindings` maps source → action, many sources to one, and
rebinding happens at run time and persists.

**`GameAction` is an open value class with equality by name**, not an enum, so a
genre adds `dash` or `reload` without editing the engine. Equality by name rather
than by reference is a save-file requirement: the config stores names, and an
action read back from a file has to be the same action.

**Held is a count, not a bit.** `W` and the up arrow pressed together and one
released must not stop the player.

**Magnitude belongs to the action rather than to a second input type.**
`InputState.value` gives 0.42 from a trigger and 1.0 from a key, and the simulation
never learns which it was. `clearActionValue` exists because a device that fell
silent holding zero would otherwise shadow the keyboard until a restart.

**Buttons are bound; axes are routed.** Binding a half-axis would run a stick
through `press`/`held` and make it digital. What a stick *means* is a property of
the genre, not a player preference.

`pad_input` covers web, Android, macOS and iOS. The rule the package is built
around is that **the native part decides nothing**: it reports which device is
connected and which axes that device admits to, forwards events, and says when the
application backgrounds. Every decision is in Dart and under test, because that is
where the difficulty is — a trigger sits on either `AXIS_LTRIGGER` or `AXIS_BRAKE`,
a d-pad is sometimes a hat axis and sometimes keys, and in the second case Flutter
delivers it indistinguishably from the keyboard, so `pad:dpad.up` is deliberately
not emitted for it rather than putting a falsehood in the player's config.

**Button names are physical positions** (`face.south`, not `a`), because the string
goes into a config read years later, possibly on another gamepad: Xbox calls the
bottom button `A`, PlayStation calls it cross, Nintendo swaps `A` and `B`.

macOS and iOS share one Swift source, since `GameController.framework` is the same
on both; the only difference is that Apple counts a stick axis positive upwards
while Android, the browser and this package count it downwards, and the sign is
flipped in Dart, once, under a test.

`pointer_lock` supplies relative mouse movement, which Flutter surfaces on no
desktop platform and does not surface in a browser either. Two backends: a method
channel on macOS, and the browser's own Pointer Lock API through static interop,
chosen by conditional export the way `pad_input` chooses its gamepad. Three rules
matter. A `reset` on construction, because a plugin outlives a hot restart and
would otherwise strand the cursor with nothing left to ask for it back. Focus loss
must **release** rather than pause, or a hidden cursor ends up over another
application's window. And in a browser the capture must be asked for inside the
handler of the press that prompted it: `requestPointerLock` is refused without a
user gesture behind it, a refusal arrives as an event rather than as an exception,
and a backend that assumed success would leave a game believing it holds a pointer
it does not.

`TouchControls` writes into the same `InputState` a key does. `Playing` answers
three separate questions — can the pointer be captured, where does camera rotation
come from, does the player have fingers instead of a keyboard — and it now asks
each of them of the thing that knows. **`kIsWeb` was the wrong question twice
over**, and both answers were wrong for a year: a desktop browser can capture a
pointer, and the web build of a first-person game was being dragged around like a
phone; a phone in a browser has fingers, and the same guard hid the on-screen
stick from every player who opened a demo on one. So capture is asked of
`PointerLockPlatform.instance.isSupported` — which also fixes Windows and Linux,
where the old platform list claimed a capture the plugin has no native side for
and then turned off drag-look, leaving a camera that could not move at all — and
fingers are asked of `defaultTargetPlatform`, which reports a mobile browser as
`android` or `iOS`.

### 11.2 Audio

Loading and streaming music, 3D positioning with attenuation and panning, voice
limits and priorities, and mix buses. `AudioBus` is an open value class like
`GameAction`, and a bus is spent when a voice is issued rather than when it is
chosen. No Doppler.

### 11.3 UI

Flutter. Unicode, DPI scaling, layout containers and world-space panels all come
free, so no immediate-mode debug UI toolkit is needed for either the overlays or
the editor.

Screen state — level loading, pause, settings, rebinding, run state — lives in
BLoC, which is what makes it reachable from a test. The boundary is drawn
explicitly: **the simulation step does not go through BLoC**, nor does the camera,
the particles or the scene. State per step would be an allocation and a widget
rebuild sixty times a second, and keeping the frame rate away from the fixed step
is what the game layer is for.

---

## 12. Extension points

Three boundaries let an application add what the engine does not ship, without
editing it. They are deliberately different shapes, because what they carry
differs.

**`ModelDecoder` — reading geometry.** Asynchronous, and it must be sendable: a
model is decoded on a background isolate, and the decoder list travels *on the
request* because statics are not shared between isolates. A registry filled at
startup would be empty in the isolate that does the reading — it would pass a test
that decoded on the main isolate and fail in the application.

**`MaterialDecoder` — reading looks.** Synchronous. A material is a few hundred
bytes of text, there is nothing to move off the frame, and there is no reason to
inherit the sendable constraint.

Both lists are consulted **before** the built-in readers, so an application can
replace a format the engine ships as well as add one it does not.

**`StepSystems` — behaviour.** A game adds a rule to the step that the genre
package never heard of. A phase is a `StepPhase`, a wrapper over a string like
`GameAction`, because "after the weapons fired" is a sentence about one genre and
an enum would mean editing the shared package the day a genre wanted its own phase.
The engine declares the two every genre has, `begin` and `end`; the rest belong to
the genre.

Phases are **announced by the game rather than imposed by the registry**, for the
reason `WorldStep` gives, and they are announced unconditionally — a phase that
exists only on levels that happen to have doors is a phase nobody can rely on.

Order within a phase is part of the contract: a system runs inside the step, so two
runs of one tape must call the same systems in the same order, or determinism is
gone. Systems run by explicit `order`, then by registration order, and never by
whatever a hash map returns.

Beyond the three: `PassContributor` extends a render pass,
`LightingModel` is open to an application that builds its own shader bundle, and
`EntityKind` catalogues are injected rather than fixed, so a level format validates
against whatever entities a game defines.

---

## 13. How correctness is held

| | |
|---|---|
| Style | `dart format` |
| Analysis | `flutter analyze` clean across the workspace, no warnings |
| Unit tests | **2950 tests** across 23 packages and 5 applications |
| Structure rules | 21, `dart run tool/structure.dart`, the first CI step |
| CI | GitHub Actions over `tool/ci.sh`, on `ubuntu-latest`, with no graphics card |

**Golden render tests.** 32 scenes against **three independent reference sets** —
Impeller, the software rasteriser and WebGL2 — each held to zero differing pixels
against its own set, with a per-channel tolerance of 8. Each backend records its
own because a shared set would need one tolerance doing two jobs: "did this
backend change" and "do two backends still agree" are different questions, and a
tolerance wide enough for the second stops watching the first.

The agreeing is then measured with no device at all, over the committed sets:
`flutter3d_cpu/test/cross_backend_test.dart` for the software backend and
`flutter3d_webgl/test/cross_backend_test.dart` for the browser one. Those run in
CI; recording needs the hardware, and for the browser set that means
`flutter3d_webgl/tool/golden_web.sh`, which builds the example for the web,
serves it, and drives Chrome once per scene — a page cannot open a file or write
one, so it fetches its reference over HTTP and posts back what it drew.

**What the third set found on the day it was recorded.** Six scenes disagreed by
whole percents rather than by a silhouette's worth, and one of the six turned out
to be a shader that drew nothing at all: `lighting-unlit` came back as an empty
frame, because the translated stage declared a `PointShadow` uniform block the
engine correctly never binds, and WebGL2 discards every draw with an active block
that has no buffer under it. The declaration is guarded at the header now and the
scene sits at 0.13% with the rest.

A second was the same kind of thing. `particles-mesh` was 19%, and the mesh
particles were never the problem: the checkerboard cube behind them came back a
flat average of itself, because the engine's only instanced draw left a vertex
attribute divisor set and the next frame's mesh read one texture coordinate for
a whole quad. Divisors are put back when a draw ends now, rather than when a
caller remembers to ask.

**None remain.** The last four went together in two fixes, and both are worth
carrying to a fourth backend because neither was visible as a wrong picture in
the thing being tested.

`bloom-sphere` at 7% and `debug-overlay` at 2.5% were one bug: the full-screen
triangle pairs clip positions with texture coordinates directly, so on a backend
whose row zero is at the bottom every full-screen pass turns its input over. One
pass that reads the frame and writes the frame survives that; the bloom chain is
a threshold, a ladder down and a ladder back — an odd number of passes however it
is configured — so the glow was composited mirrored about the middle of the
frame, which is exactly where every scene in the golden set keeps its subject.

`view-model-point-shadow`, `cube-shadow-mover` and `cube-shadow-lit` were the
point-shadow lookup, and the instrument was the problem. The cube atlas is stored
bottom-up on this backend, so a light in slot zero is drawn into the row the
shader would call three and the picture inside that tile is upside down as well;
turning the whole atlas over in the lookup fixes the row and the tile together.
Read that beside the three scenes that were **exactly zero** throughout —
`cube-shadow`, `cube-shadow-many` and `cube-shadow-crowded` composite the atlas
rather than light with it, a composite is a full-screen pass, and a full-screen
pass turned its input over. The view built to check the atlas cancelled the very
error it was pointed at and agreed with Impeller to the pixel for six sessions.

What holds it now is `flutter3d_webgl/test/cross_backend_test.dart`: a budget per
scene, all thirty-two of them between 0.01% and 0.6%, measured rather than
rounded — a budget far above what was observed has stopped watching.

**Every new test is written by breaking what it covers**, and the mutation is named
in the test's comment. This is not a ritual: the rule regularly finds tests that
cannot fail — one reading a single pixel, one that never built the pipeline it
claimed to check, one asserting a neighbouring class's guarantee. Two Dart-specific
traps recur and are worth naming: two `const` expressions are canonicalised into
one object, so value equality cannot be checked with them, and a harness that
releases a button every step never tests what holding it does.

**Documents are compared against the tree.** The test count, the structure-rule
count and the publishing order each have a scan, because a number in prose is a
number nobody recounts — the test count said "1230 tests in 12 packages" when there
were nearly three thousand. What a scan catches is not a wrong number but a
document quietly describing the repository of a year ago.

**Generated files are diffed.** Anything produced by a tool is regenerated in CI
and compared with `git diff --exit-code`, and the shader bundle — which is
gitignored — is checked by freshness against its sources instead.

**`flutter3d_testing`** renders a scene through the software backend and compares
it against a reference image, so a game built on the engine gets pixel regression
tests on a machine with no display. Its tolerance defaults to zero: the same scene
drawn twice is the same bytes twice, and a test that allows a few pixels of drift
is a test that has stopped watching.

**What CI does not run:** the Impeller half of the golden set, which needs a
device and runs from `tool/golden.sh` on a machine with a GPU; and the performance
budgets, for which there is neither a profiler nor a stored baseline.

---

## 14. Performance characteristics

Measured with `tool/bench/bench.dart` compiled through `dart compile exe` — the
same AOT pipeline a release build uses — on macOS arm64. Frame budget: 16.6 ms at
60 Hz, 8.3 ms at 120 Hz.

| Operation | Time | Per unit |
|---|---|---|
| OBJ teapot, full load with smooth normals | 5.39 ms | 2387 ns/triangle |
| GLB `BoxTextured`, full load | 14.8 µs | — |
| `SphereShape.build`, 33k vertices | 888 µs | 26.8 ns/vertex |
| `MeshData.transformed` | 545 µs | 16.4 ns/vertex |
| Frustum cull, 50k bounding spheres | 728 µs | 14.6 ns/object |
| Sort 50k draws, `sortPackedKeys` | 1.26 ms | 25.1 ns |
| Sort 40 draws (what a plain scene reaches) | 3.4 µs | — |
| Compose 50k world matrices | 778 µs | 15.6 ns/node |
| Navigation wave on a cell change | 0.65 ms | on `crypt.json` |
| Navigation mesh bake at load | 73 ms | 55×96 cells |

Two of these numbers are the reason parts of the architecture look the way they do.

**Sorting 50k draws took 13.2 ms with a closure comparator** — three quarters of a
frame — and looks like the ideal candidate for native code. A radix sort **in the
same Dart** brings it to 1.26 ms. The problem was asymptotics and data layout, not
the language, and a naive comparison sort in C would be slower than a radix sort in
Dart.

**A binary format is 360× faster than text**, which no parser rewrite closes. That
is why `.f3d` exists.

Everything else already fits: 14.6 ns per culled object and 15.6 ns per node are
numbers Dart AOT handles fine, because `Float32List` and `Int64List` compile to
plain memory access with no boxing. A realistic gain from rewriting such loops in C
is 2–4× through SIMD, not an order of magnitude — so **there is no FFI in this
project**, and the case for adding it would have to be a capability rather than a
speed: a Draco decoder, a KTX2 transcoder, or an audio engine. Native code also
costs a signed dylib per platform, a build per Android ABI, two debugging
toolchains, and `SIGSEGV`s with no Dart stack; and it does not cure jank, since a
native call from the UI isolate blocks it exactly as Dart does.

---

## 15. Limits

What the architecture does not provide, and why.

**No runtime shader compilation**, and therefore no material graph in the running
game. A designer-facing graph is possible in an editor that generates permutations
into a bundle.

**No compute**, and therefore no GPU particles, GPU skinning, GPU culling or
indirect draw.

**No compressed textures in use**, so every texture costs its uncompressed size.
SDK 3.47 exposes block-compressed formats; nothing here consumes them yet, and
KTX2/Basis transcoding has no Dart implementation.

**No morph targets**, no animation blending or crossfade, and therefore no useful
animation state machine — a crossfade is useful on its own, and a state machine
without one is not.

**No shadows past `ShadowSettings.viewDistance`**, which defaults to sixty
metres. The directional light's cascades fit the view up to that distance and
nothing beyond it casts — a level whose far end matters visually wants the
number raised, and pays for it in texels.

**The web backend now draws all thirty-two golden scenes the way Impeller does**,
between 0.01% and 0.6% of pixels differing by more than 8 per channel — the
silhouette's worth of disagreement two rasterisers always have. Six scenes were
in whole percents and every one of them was this backend drawing something else;
[§13](#13-how-correctness-is-held) keeps what each turned out to be, because in
all six the picture was wrong in a place nothing was looking.

Custom materials and fog still have no web comparison at all: they are drawn
there, and nobody has checked they are drawn the same. That gap is worth stating for
what closing part of it produced — three new parity fixtures found the sky
blacking out every frame, and a reference set of thirty-two found a lighting
model drawing nothing.

**No occlusion culling, FXAA or TAA.** Screen-space ambient occlusion and
reflections exist and are off by default; neither has a golden scene, so what
is pinned about them is their settings and their shader, not their picture.

**No convex hulls or triangle-mesh collision shapes**, and no joints.

**No shader or asset hot reload**, no levelled logging, no console or cvars, and no
crash reporting.

**No asset streaming**, no load priorities and no cancellation. Streaming is only
needed for open worlds, and there is no such scenario here.

**No frame profiler yet**, which is why several entries in
[§14](#14-performance-characteristics) are per-subsystem rather than per-frame:
an external profiler sees Dart calls without knowing which part of a frame they
are.

**No multithreading of the simulation.** Dart isolates do not share memory, so
moving the step to a thread is a message protocol and a copy of the frame's state
rather than a flag.

---

## 16. Distribution

Everything is prepared to publish and **nothing is published**: every package
carries `publish_to: none`, which is the one line between "prepared" and "on the
internet".

- **Licence: MIT**, `Copyright (c) 2026 Dmitrii Zolotov`. One `LICENSE` at the root
  and a copy in every package, because pub wants the file inside the archive.
- `LICENSE`, `CHANGELOG.md`, `README.md`, `repository:` and `homepage:` in all
  twenty-three packages.
- **`dart format` is a CI step**, second in the order and reported by
  `tool/ci.sh`. It was this document's claimed style for a year with nothing
  checking it, and 637 files of 874 did not match — Dart 3.7 changed the
  formatter and a repository nobody reformats stays in the old shape. `pana`
  scores formatting, so this is a published package's grade as well as a
  reader's diff.
- **Sibling dependencies are version constraints, not paths.** `pub publish`
  refuses a path dependency, and a workspace resolves `flutter3d_hardware: ^0.1.0`
  from the checkout anyway, so one line works for both a developer and the server.
- `tool/publish_check.sh` runs `pub publish --dry-run` for every package with
  `publish_to` temporarily removed and puts the line back, so a package that loses
  its licence or grows a path dependency is caught on the day rather than on
  publishing day.

**The order, when the day comes**, is set by the dependency graph:

1. `flutter3d_hardware`, `flutter3d_shaders`, `flutter3d_samples`,
   `flutter3d_audio`, `pad_input`, `pointer_lock`
2. `flutter3d_conformance`
3. `flutter3d`, `flutter3d_physics`
4. `flutter3d_impeller`, `flutter3d_webgl`, `flutter3d_cpu`, `flutter3d_particles`
5. `flutter3d_game`
6. `flutter3d_ui`, `flutter3d_bridge`, `flutter3d_backend`, `flutter3d_testing`
7. `flutter3d_session`
8. `flutter3d_app`
9. `flutter3d_game_shooter`, `flutter3d_game_platformer`, `flutter3d_game_racing`

Two positions are not obvious and so are written down rather than re-derived:
`flutter3d_samples` is in the first tier although nothing depends on it at run
time, because `flutter3d`'s tests do and a dev dependency has to resolve for the
archive to be accepted; and `flutter3d_app` is second to last because it is the
assembly layer.

**The applications are not packages.** `apps/` keeps its path dependencies: three
demo games and an editor are things to clone, not things to depend on.

**Most packages have no `example/`.** pub scores a package higher with one, and an
example nobody runs is worse than none. `packages/pad_input/example` exists because
its tests are the only ones that drive the tool a controller is accepted with; the
rest are demonstrated by `apps/`.
