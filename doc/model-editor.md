# A 3D model editor on flutter3d — a working-through

Draft from 2026-09-09. Source material — the "3D editor with Material
Design" handoff archive (a handoff README, 19 screens, a four-phase
development plan). Both copies of the archive in `~/Downloads` are
byte-identical.

This document answers the development plan's first question — "how ready is
flutter3d today: what already works, what needs to be written for the
editor" — and proposes how to lay the editor onto this repository.
Everything said about the engine was checked against the code at commit
`239ccf8e`, not against documentation.

---

## 1. In short

**The viewport, materials, skeleton, animation, and import already exist.**
A scene, an orbit camera, six lighting models, PBR metal-rough with
textures and IBL, eight light sources, shadows, GPU skinning up to 64
bones, GPU morph targets, an animation player with layers and masks, LOD
groups, per-pixel picking and triangle raycasting, glTF/GLB, OBJ, and
`.f3d` decoders, four backends, one of them software and producing golden
frames with no GPU. Phase 0 of the plan ("does Flutter handle a real
scene") is half-closed by existing code; only a measurement on
million-triangle meshes remains open.

**Nothing that *changes* geometry exists at all.** No editable topology, no
mesh operations, no modifiers, no boolean operations, no glTF/OBJ/STL
writing, no vertex/edge selection, no move-and-rotate manipulator, no
parametric objects. This is the bulk of phase 1, and it's entirely new
code.

**The design diverges from decisions already recorded in the repository in
three places:** a material node graph (ROADMAP: "not doing this"), offline
rendering with samples (the engine has no such thing), and an undo model
(the level editor stores whole-document snapshots, which doesn't work for
a million-vertex mesh). All three were resolved 2026-09-09 (§4, §7).

**Proposal:** three new pure-Dart packages, one MCP server, and one
application, in this same monorepo, following the same shape the level
editor already uses (§5). After the owner's 2026-09-09 decisions (§7), two
vocabulary packages, split out of `flutter3d`, were added to these (§5.1),
and the web and mobile platforms entered phase 1 on equal footing with
macOS.

---

## 2. Screens versus the engine

What already exists for each screen, and what doesn't. "Exists" means "in
the repository and covered by tests," not "planned."

| Screen | Phase | Exists in the repository | Missing |
|---|---|---|---|
| 01 Object | 1 | `Scene`/`SceneNode`, `OrbitController`, `Renderer.pickPixel`, `Raycaster`, `Shape` with every primitive, `LodGroup`, `DebugDraw` lines | an XYZ manipulator (the level editor only has selection-box edges), a modifier stack, booleans |
| 02 Mesh | 1 | `MeshData`/`MeshBuilder`/`VertexLayout`, `rayTriangle`, line overlays, tangent generation | a half-edge structure, vertex/edge/face selection, extrusion, bevel, loop cut, merging, n-gon and non-manifold checks |
| 03–04 Tablet, phone | 1 | responsive screens in `flutter3d_screens`, touch controls in `flutter3d_game` | the whole editor UI |
| 05 Material | 2 | `SurfaceMaterial`, `.fmat` with `MaterialHint` (the inspector is built from hints, already implemented in `material_panel.dart`), a preview in `RenderView` with IBL | a node graph — see §4.1 |
| 06 UV | 4 | UV in the vertex format, a second `RenderView` for the 2D unwrap | unwrapping, island packing, stretch metrics |
| 07 Animation | 3 | `Skeleton`, `AnimationClip`/`Track` (step, linear, cubicSpline), `AnimationPlayer`, layers, masks, `BakedPoses` | a keyframe/curve editor, IK |
| 08 Sculpting | 4 | nothing specific | brushes, multiresolution with a "Subdivide" button (item B9, 2026-09-09 decision), a measurement on 1.2 million triangles |
| 09 Lathe | 1 | `LatheShape` with an arbitrary profile, all derived shapes | a profile editor (UI), a parametric object in the document |
| 10 Retopology and baking | 4 | `GraphicsDevice.readback`, render-to-texture | everything else |
| 11 Simulations | 4 | CPU particles, non-rotating `RigidBody` | cloth, body rotation (ROADMAP: "not doing this"), a frame cache |
| 12 Render and compositing | 4 | a frame graph, bloom, SSAO, reflections, auto-exposure, `composite_mix` | ray tracing with samples — see §4.2; a compositing graph |
| 13 Weights | 3 | 4 influences per vertex in the format, `Skeleton` | a weight brush, renormalization, gradient painting |
| 14 Retargeting | 3 | a player, layer blending | bone mapping, a clip library, root motion |
| 15 Morphs | 3 | `MorphTarget`/`MorphBlend`, `MorphSink`, exporting morphs to `.f3d` | on-timeline keys, bone-angle correction shapes |
| 16 Auto-rig | 3 | nothing | everything |
| 17 LOD | 4 | `LodGroup` with distances, three side-by-side `RenderView`s | mesh simplification preserving UV and weights |
| 18 3D painting | 4 | render-to-texture | everything |
| 19 "In-game" preview | 3 | **this is literally the engine**: the same shaders, the same bone limit, frame counters; `flutter3d_app` already supports a widget texture | a project profile with budgets |
| Import with checks | 1 | `ModelDocument.warnings` on every decoder, a background isolate (the main thread on the web) | the screen isn't drawn |
| Export with checks | 1 | `F3dWriter` as a writer template | **no glTF/GLB, OBJ, or STL writers**; the screen isn't drawn |

Two rows deserve their own note.

**Screen 19 is the design's strongest point, engine-wise.** "The same
runtime as the game" is literal truth here, not a promise: the editor and
the game share one `Renderer`, one shader bundle, one
`Skeleton.maxJoints`. The preview comes almost for free, and profile
budgets (triangles, bones, texture weight) are already computed by the
engine: `MeshData.triangleCount`, texture sizes in `TextureUpload`, bone
count in `Skeleton`.

**Screen 09 is the second.** `LatheShape` already accepts an arbitrary
profile, so a lathe object is just a profile editor plus storing the
profile in the document as a parameter — exactly what the design calls "a
shape stored parametrically."

---

## 3. What we take from the level editor as-is

`flutter3d_editor_core`, `flutter3d_editor_mcp`, and `apps/flutter3d_editor`
have, over recent weeks, arrived at a shape the model editor doesn't need
to reinvent — it needs to copy:

- **A command as a value.** `EditorCommand` — a sealed class with a name,
  `says` (a sentence for the status line and history), `arguments` (JSON),
  and `apply`. Hotkeys and the MCP tool table are both built from one
  command list. This is exactly "every edit goes through a command" from
  the handoff README.
- **History with transactions.** `EditorHistory.transaction` — one step
  per whole drag, not per mouse event. The snapshot mechanism inside it
  will need replacing for meshes (§4.3); the shape stays.
- **An inspector built from hints.** `MaterialHint` describes a control,
  not a value; `material_panel.dart` assembles the panel from hints. Screen
  05's right panel ("sliders for the simple case") is exactly this.
- **Documents and disk.** `documents.dart`, `recent_projects.dart`,
  `file_selector`, "open — offer a template if there's no path" — carries
  over unchanged.
- **A Cubit/State split.** `EditorState` holds what a screen rebuilds on;
  the camera, the scene, and gizmos live in the widget's `State` and never
  go through the bloc. For a 60-fps viewport, this is the only workable
  shape.
- **Tests with no GPU.** `pick_pixel_test`, `drag_test`, `frame_test` in
  the level editor run through the software rasterizer. The new editor
  inherits this too.
- **MCP as a second user.** The level editor's seventeen tools are the same
  commands over stdio. For the model editor this is separate value: "an
  agent assembles an asset from primitives" is a scenario Blender doesn't
  have.

What **not** to take: `Piece` (brush / light / entity) and `Editing`. A
level document and a model document are different things, and one class
for both would be exactly the mistake `gizmos.dart`'s own header already
describes.

---

## 4. Where the design diverges from the repository

### 4.1 A material node graph (screen 05, screen 12)

The ROADMAP, under "Not doing": *"Node-graph materials. There is no shader
compilation at runtime here, and a graph that cannot produce a new shader
is a picture of one."* This is a channel limitation, not a choice: shaders
are compiled ahead of time into a bundle, one permutation per lighting
model.

Three ways out:

1. **A graph as a texture compositor.** "Texture," "Blend," "Color" nodes
   are computed on the CPU (or in a render-to-texture pass) and *baked*
   into the slots the fixed PBR shader reads. The graph stays, the shader
   doesn't. Screen 05's own mockup is exactly this: texture → blend →
   principled PBR.
2. **Defer the graph until the bundle can be assembled from the editor.**
   ARCHITECTURE §15 allows for a "designer-facing graph… that generates
   permutations into a bundle" — but that's an offline build through
   `impellerc` and `naga`, not at runtime and not on the web.
3. Drop the graph from phase 2, keep sliders.

**Recommendation:** option 1 for materials, and the same for compositing
(screen 12): frame graph passes already exist, a graph can just enable them
and turn parameters. The design's own wording of "graph" is worth
tightening to "a graph over a fixed set of nodes."

**Decision made 2026-09-09 (owner):** a texture compositor with a fixed
node set; the ROADMAP gets reworded at the September 28 review.

### 4.2 A "render" with samples (screen 12)

`256 / 256 samples · 1 min 12 s` describes a path tracer. The engine has
none, and the ROADMAP doesn't plan one. What exists: the software
rasterizer `flutter3d_cpu`, which draws the same 43 golden scenes as the
GPU and can do so at any resolution with no GPU. The first version's
"render" is the same 4K frame with supersampling — honestly called a
"snapshot." A path tracer is a separate project, outside this write-up.

**Decision made 2026-09-09 (owner):** a snapshot from the same renderer
with supersampling and frame-graph passes; a path tracer is out of scope.

### 4.3 The undo model

`EditorHistory` stores a snapshot of the **whole document** before every
step, and `editor_command.dart` explains why: "an undo that reconstructs
state is an undo with its own bugs," and a level is a few hundred
numbers. The ROADMAP still talks about `apply` and `revert` — the text has
fallen behind the code there.

For a mesh this doesn't work: a whole-document snapshot with a
200,000-vertex mesh on every stroke is gigabytes per minute of sculpting.
A third option is needed, and there's only one:

- the document stores meshes as **immutable values with structural
  sharing** (persistent data): an operation returns a new mesh, sharing
  with the previous one everything it didn't touch;
- a history snapshot is then just a reference to the prior value, and its
  cost equals the size of what changed;
- the "undo has its own bugs" argument still holds: there's still no
  inverse operation, going back is still substituting the prior value.

This decision is made before a single line of `flutter3d_mesh` code,
because it sets the shape of the data structure.

**Decision made 2026-09-09 (owner):** persistent values with structural
sharing. Chunking versus patches, and the cost of a snapshot, are measured
by phase 0 (plan item p0-05) — that's already a measurement, not a choice.
History is also written into the project file — a `history` section
referencing chunks that already sit in the file as blobs (plan, doc-31d).

### 4.4 Small divergences worth knowing about

- **Bones:** `Skeleton.maxJoints = 64` — a hard bundle limit. The mockup's
  "28 of 64" matches, but a project profile can't set a higher number
  without rebuilding shaders.
- **Light:** eight sources per scene. Enough for screen 19, not always
  enough for a scene screen; the ROADMAP has per-object light lists.
- **Wireframe:** `supportsWireframe` — absent on OpenGL ES and WebGPU. Edges
  in "Mesh" mode are drawn as lines (`PrimitiveType.line`, the mechanism
  `DebugDraw` already uses), the same way on every backend. This is better
  than polygon mode: color, thickness, and edge highlighting are all
  data-driven.
- **Web and isolates:** `decodeModelInIsolate` falls back to `decodeModel`
  on the main thread on the web. "Heavy operations in an isolate" from the
  handoff README means, on the web, "on the main thread with a frame
  yield," or a web worker, which the repository doesn't have.
- **Web and files:** the level editor is declared desktop-only precisely
  because "a browser won't write a file over itself." The model editor
  needs writing through a download and opening through `file_selector` for
  the web, and this is a separate phase-1 item, not a detail.
- **Updating a mesh on the GPU:** `DeviceMesh.upload` is a one-shot load;
  there's no "replace the vertices" method. Every edit today gets a new
  `DeviceMesh`. Fine for phase 1 (tens of thousands of triangles); sculpting
  needs a partial buffer rewrite path, and that's a `flutter3d_hardware`
  change with a conformance test across all four backends.
- **Sub-element selection:** the id pass writes an *object* number, not a
  face; WebGL2 has no `gl_PrimitiveID`. Vertices, edges, and faces are
  picked on the CPU — `Raycaster` with `rayTriangle` already exists, a BVH
  over the editable mesh is needed.
- **Simulations:** the engine's physics has no body rotation, no cloth, and
  the ROADMAP files rotation and joints under "not doing this." Screen 11
  is a separate solver, not an extension of `flutter3d_physics`.

---

## 5. Architecture

### 5.1 Packages

The layout was rewritten 2026-09-09 per an owner decision (plan §1 item 1,
§3.1): two vocabulary packages, split out of `flutter3d`, were added to the
three editor packages.

```
flutter3d_geometry      pure Dart   MeshData, VertexLayout, Shape/LatheShape,
                                    tangents, morph_target, CpuMesh,
                                    math/intersections, Ray, TriangleBvh
flutter3d_formats       pure Dart   ModelDocument, SurfaceMaterial,
                                    MaterialDocument/MaterialHint, lighting_model,
                                    the synchronous half of model_loader,
                                    gltf/obj/f3d/ktx2/stl decoders,
                                    F3dWriter/GltfWriter/ObjWriter writers
flutter3d_mesh          pure Dart   editable topology and operations
flutter3d_model_core    pure Dart   the document, commands, history, checks, export
flutter3d_model_mcp     pure Dart   the same commands over stdio for an agent
apps/flutter3d_modeler  Flutter     the shell, viewport, panels, disk
```

Plus engine changes (partial buffer rewrites, a couple of overlays, `Pose`
and IK) — all of these are also needed by games, so they go into the
engine, not the editor. Format writers are also needed by games, but live
in `flutter3d_formats` so the MCP server can export a GLB with no Flutter.

Dependencies:

```
apps/flutter3d_modeler ──► flutter3d_model_core ──► flutter3d_mesh
        │                    │           │                 │
        ▼                    ▼           ▼                 ▼
    flutter3d ──────► flutter3d_formats ──► flutter3d_geometry ──► vector_math
  (rendering, RenderView,   (document, decoders,   (mesh, shapes, rays, BVH)
   picking, camera;          writers)
   re-exports both)
```

Why the vocabulary was split out rather than taken from `flutter3d`:
`packages/flutter3d/pubspec.yaml` declares `flutter: sdk`, and any package
depending on `flutter3d` inherits the Flutter SDK transitively —
`flatDartPackages` in `tool/structure/repository.dart` can't see this, and
`dart pub get` in a container with no Flutter can't resolve it.
ARCHITECTURE §8.1's promise (a "`ModelDocument` layer with no Flutter")
only becomes checkable through a package that doesn't declare Flutter. So
`flutter3d_model_core` depends on `flutter3d_formats` and
`flutter3d_geometry`, `flutter3d_mesh` depends on `flutter3d_geometry`, and
`flutter3d` re-exports both, with nothing changing for games. Publishing
order: geometry → formats → flutter3d; by the end of phase 0 the tree holds
33 packages. Later come `flutter3d_fbx` (its own FBX reader over `formats`,
phase 2), `flutter3d_rig` (phase 3), and `flutter3d_cloth` (phase 4).

### 5.2 `flutter3d_mesh`: topology

**`EditMesh`** — a half-edge structure with faces of any valence. Not
`MeshData`: that stores GPU-interleaved triangles and can't answer "which
faces touch this edge." `EditMesh` answers that, and `toMeshData()`
triangulates, computes normals, and hands the result to the engine. The
reverse path, `EditMesh.fromMeshData()`, welds vertices by position and
reconstructs edges, keeping UV and weights as corner attributes.

Storage — typed arrays (`Int32List` for connectivity, `Float32List` for
attributes) with indices instead of objects: ARCHITECTURE §2 explains that
every `Vector3` is a heap object and GC eats into the frame budget.
Persistence (§4.3) is done in 1024-element chunks with copy-on-write.

**Operations** — pure functions `EditMesh × Selection × parameters →
EditMesh`:

| Phase 1 | Phase 2 |
|---|---|
| selection: vertices, edges, faces, loop, ring, grow | bevel |
| move, rotate, scale a selection | inset |
| face and edge extrusion | subdivision (Catmull-Clark) |
| loop cut | booleans: union, subtract, intersect |
| weld vertices by distance, dissolve an edge | smoothing, mirror symmetry as an operation |
| delete, split into objects | UV unwrapping — phase 4 |
| n-gon triangulation, normal recomputation | |

**Modifiers** — the same functions, but recorded onto an object and applied
at every `toMeshData()`: mirror, array, smoothing, boolean. Screen 01's
modifier stack is a list of such values; "apply" means replacing the mesh
with the result.

**Checks** — what feeds the status line: n-gons, non-manifold edges,
inverted normals, isolated vertices, triangle count after triangulation.
Each is a function with a test.

**Parametric objects** — `Lathe(profile, segments, angle, smooth, caps)`
and primitives are stored as parameters, and `EditMesh` is built from them
on demand through the existing `Shape` types. The first manual vertex edit
"bakes" an object into a mesh — with a warning, as in the mockup.

**Boolean operations** — the one item in phase 1–2 worth taking a known
algorithm for rather than inventing one: a BSP approach on triangulated
meshes (as in csg.js) is simple, testable, and predictably poor on coplanar
faces — which is honestly flagged in the UI. Exact arithmetic can come
later, if needed.

### 5.3 `flutter3d_model_core`: the document

```
ModelProject
  profile        ProjectProfile: triangle, bone, influence, and texture limits
  objects[]      ModelObject: name, transform, parent,
                   geometry: Parametric | Edited(EditMesh) | Imported(MeshData)
                   modifiers[], materialSlots[]
  materials[]    SurfaceMaterial + a .fmat path if the material is external
  skeletons[]    joints, inverse bind — the same shape as ModelSkin
  clips[]        AnimationClip
  selection      mode, submode, objects, element level, elements
  history        steps: says + the document's prior value (structurally shared)
```

**Export** — `project.toModelDocument()`, then any writer. `ModelDocument`
is already the sole entry point into `ModelAsset.fromDocument()` and into
`F3dWriter`; glTF and OBJ writers sit alongside it and get mesh/image
deduplication for free. **Import** is the reverse: any decoder →
`ModelDocument` → `ModelProject.fromModelDocument()`, and the document's
`warnings` become the import screen.

**The project format** — its own, JSON plus binary blobs following the
`.f3d` pattern (aligned sections, an unknown section is skipped). Not
glTF: glTF has no room for a profile, lathe parameters, a modifier stack,
or history. glTF is an *output* format.

**Commands** — a sealed hierarchy following `EditorCommand`'s own pattern,
with one addition: a mesh command carries a `Selection`, not just
parameters, so an operation replays from the MCP log. A transaction wraps
a drag.

**Export checks** — `ExportReadiness(project, profile)` returns a list of
`Issue(severity, text, objectId)`; the status line shows the first one, the
export dialog shows all of them. Computed after every command, cheaply,
because it's cached by object version.

### 5.4 What to add to the engine and vocabulary

| What | Where | Why | Test |
|---|---|---|---|
| `GltfWriter` (GLB and `.gltf` + `.bin`) | `flutter3d_formats`, next to the glTF loader, mirroring `F3dWriter` (2026-09-09 decision: writers go into the vocabulary package, not `flutter3d`) | phase-1 export | round-trip on Khronos models from `flutter3d_samples`: decode → write → decode → documents are equal; plus a golden frame of both |
| `ObjWriter` with `.mtl` | `flutter3d_formats`, next to the OBJ loader | phase-1 export | the same round-trip |
| `StlLoader` (ASCII and binary) | `flutter3d_formats`, as a `ModelDecoder` | phase-1 import | Khronos-like fixtures, three files |
| `DeviceMesh.overwrite(vertices, range)` | `flutter3d_hardware` + all four backends | sculpting, dragging vertices with no re-creation | conformance: overwriting part of a buffer draws the same as a fresh upload |
| Vertex and edge overlays | a `PassContributor` on `PrimitiveType.line`/`point` | "Mesh" mode | a `mesh-overlay` golden frame across all four sets |
| `Skeleton`/`AnimationClip` — writing into `ModelDocument` | already exists for `.f3d`, check for glTF | phase-3 animation export | `simple_skin`, `BoxAnimated` round-trip |

None of these changes alters the backend contract except `overwrite`; that
one goes through the conformance suite, like any `GpuDevice` change.

### 5.5 `apps/flutter3d_modeler`

The shell — per the handoff README: an M3 theme from the token table, a
mode `SegmentedButton`, a 52-wide `NavigationRail`-like rail, a 250–330
properties panel, a 30-tall status bar. Three layouts by width class, one
set of tools.

The viewport — a `Renderer` inside `Texture.asImage()` inside a widget, as
in the level editor. The camera — `OrbitController`, not the level
editor's fly camera: a model gets orbited, a level gets flown through.

Panels — widgets reading `ModelProject` through a Cubit; every edit is a
command. "Mesh" mode's right panel is a last-operation card: once a
transaction closes, the command with its parameters sits at the top of
history, and the card edits its parameters and reapplies the command over
the prior value (exactly what a persistent mesh makes cheap).

---

## 6. Phases 0 and 1 in detail

Sizes: S — up to a week, M — two to three weeks, L — a month or more, for
one person familiar with the repository. This is an order of magnitude, not
an estimate.

### Phase 0 — measurements and a spike (answering "does it hold up")

| # | What | Size | What counts as an answer |
|---|---|---|---|
| 0.1 | A 1-million-triangle scene on macOS, in Chrome (WebGL2 and WebGPU), on a Galaxy A55 | S | frames per second and load time, recorded HANDOFF-style |
| 0.2 | An `EditMesh` spike: a half-edge cube → a face extrusion → `toMeshData()` → a frame | M | operation tests with no GPU; a golden frame via `flutter3d_cpu`; a `toMeshData` measurement at 50k and 200k triangles |
| 0.3 | A persistent mesh: the cost of a history snapshot on 200,000 vertices when moving 1% of them | S | bytes per step and time; if > 10% of a full copy, the chunk structure is wrong |
| 0.4 | The structure scanner on the five new pure-Dart packages (geometry, formats, mesh, model_core, model_mcp) | S | `dart run tool/structure.dart` is green with the packages in `flatDartPackages` |
| 0.5 | Web: open a GLB via `file_selector`, save via download, on `--wasm` | S | opens and downloads in three browsers — or whatever closes the gap enters phase 1 (a JS build as a recorded exception, a custom wrapper via `package:web`, a worker for a freeze longer than a second) |

If 0.1 or 0.5 don't pass on the web, the web stays a phase-1 platform: the
unmet threshold becomes a phase-1 item (§7, 2026-09-09 decision).

#### What phase 0 answered, in one table

A p0-12 rollup. Full numbers and how they were taken follow below; this
only gives the outcome and what it changed.

| Measurement | Result | What was decided |
|---|---|---|
| p0-01 rig | the `flutter3d_modeler` app with `--dart-define=stress/objects/orbit/churn` | the rig is shared between macOS and web, a report is printed and shown on screen |
| p0-02 macOS | 1 million triangles — 8.33 ms frame, 1.02 ms `render`; 1000 draws — 27 ms | the project budget counts **objects**, not triangles |
| p0-02 browser | doesn't start under `--wasm`, works under dart2js | **phase-1 web is a JS build**, a recorded exception; the wasm failure's cause is a separate item |
| p0-03 Android, iPad | not measured — needs the devices | stays with the owner, by mid-phase-1 (rel-19d) |
| p0-04 `EditMesh` spike | 200k: `toMeshData` 59 ms, an in-place-rebuild operation ≈1 ms | in-place editing (`mesh-11`) and `fillVertices` (`mesh-14`) — a condition for interactivity |
| p0-05 history | a log of prior values costs 2% of a copy under both distributions; chunks — up to 100% | **chunks are rejected**: a flat array + a log |
| p0-06 buffer upload | `DeviceMesh.upload` 1.24 ms at 200k, 5.39 ms at 1 million | `overwriteGeometry` → phase 4, `view-14` removed from phase 1 |
| p0-07 isolate/chunks | an isolate costs ≈0 overhead; 32 chunks — worst 2.1 ms | operations are step-based from day one, an isolate on native is free |
| p0-08 files in the browser | a custom wrapper over `package:web` was written, a JS build with buttons works | a live run in three browsers is a manual step |
| p0-09 packages with no Flutter | 6 flat packages resolve via `dart pub get` with no Flutter SDK; a scanner rule + a CI job | closed |
| p0-10 picking | a ray at 2.2–3.8 μs versus 1.2–23 ms by brute force; build at 200k — 61 ms | picking stays on the CPU |
| p0-11 end-to-end pipeline | 200k: 1.8 ms per frame, 0 slow frames; 1 million: 12% of frames run late | an API on values up to 200k; `toMeshData(into:)` — above that |
| p0-13n macOS sandbox | the container: both a direct write and temp+rename work | autosave with no caveats; a user-selected path is a manual step |
| anim-31 FK | 17.5 μs per pose across 64 bones | FK isn't phase 3's bottleneck |

| qa-13 CI bench | `bench-mesh` is built with `dart compile exe` and attached as an artifact on every push | numbers stopped being taken once, on one machine |
| p0-02 macOS, re-checked | 1 million in one draw — 8.33 ms frame, 0.64 ms `render`, 0 frames over 16.6; 1000 draws — 29.11 ms frame, 24.49 ms `render`, 114 of 227 run late | confirms the earlier finding: the budget counts **objects**, not triangles |
| golden frames on Impeller | 43 of 43 matched byte-for-byte (0 pixels out of 172,800 in each) | the half of the set `tool/ci.sh` doesn't take was captured manually on GPU |
| p0-13n macOS panel | the container and the home directory: both a direct write and temp+rename work; `HOME` is inside the container | writing through the panel still requires a human: the panel doesn't answer the process |
| fmt-13 `encodeModelInIsolate` | 199,712 triangles (a 317×317 grid, 100,489 vertices): `glb` 18.6 ms, `obj` 207.2 ms, `f3d` 7.0 ms, `stl` 64.2 ms synchronously; through an isolate — 18.7 / 177.5 / 7.5 / 48.8 ms, byte-identical (`glb`/`f3d`/`stl` byte-identical, `obj` the same text) | the isolate costs roughly nothing, like p0-07; the text-based `obj` is an order of magnitude more expensive than binary formats, which is about the codec, not the isolate |
| fmt-27 `UsdzWriter`, Box.glb | a real `.usdz` from `GltfLoader().load(Box.glb)` was checked with macOS's own `unzip -l`/`zipinfo -v` (a valid archive, a correct CRC-32, 1 entry) and `mdls` (`kMDItemContentTypeTree` names `com.pixar.universal-scene-description-mobile`/`public.3d-content`, MIME `model/vnd.usdz+zip` — the system recognizes the file as a genuine USDZ); the `.usda` entry's data offset — 64 bytes, `% 64 == 0`, computed independently in Python against the same fields `UsdzZip` writes | the alignment is confirmed independently of the writer's own code; there is no Quick Look screenshot for this item — see below for why |
| pro-sc-01 stroke at 1.2 million | macOS: opening+BVH 3.3–5.7 s (the 3 s threshold is not met); a stroke (selection+edit+normals+overwrite+raycast) 294–1005 ms (the 8/16 ms thresholds are missed by 20–60×, the bottleneck is a full normal recompute). Chrome: opening+BVH 24.2–24.4 s, a full stroke 7.58–7.71 s (both thresholds missed, ~4–5× slower than macOS — the cost of JS/wasm with no SIMD). The A55 wasn't measured | `pro-sc-02` (chunked `SculptMesh` + local normals) is needed before a stroke can become interactive at 1.2 million; the `pro-sc-09` web limit should be based on whatever size passes this same budget |
| pro-sc-01 re-measured with `MeshNormals.rebuildAround`, 2026-09-17 | macOS: setup 1.87 s (**passes** 3 s); a stroke 38.2 ms (misses 16 ms by 2.4×, where it used to miss by 20–60×) — normals 17.4 ms against the whole-mesh path's 156.7 ms in the same sitting, selection 15.1 ms. Chrome: setup 24.87 s, a stroke 396.87 ms, nineteen times cheaper than the 7.58 s it was. The A55 still wasn't measured | normals stop being *the* bottleneck and become one of two: the selection scan over all 602k vertices now costs as much as they do, and it is what `pro-sc-02`'s chunking was always for. `pro-sc-09`'s limit should be measured at a candidate size rather than extrapolated from this one, because the two remaining costs scale differently — one with the mesh, one with the brush |

Not measured, and none of it needs code, only a machine or a person: p0-03
(needs a Galaxy A55 and an iPad), frame numbers in the browser (needs
`profile_web.py` and three browsers), writing to a file chosen through the
macOS panel (needs one click in a panel CI can't show), `syn-02` — two
screen mockups, which is design work, and now also **fmt-27's Quick Look
screenshot**: `qlmanage -t` for `.usdz` hangs with no response in this
automated shell (for an ordinary file — a text `.txt` — the same command
finishes in seconds, so `qlmanage` itself works; it's specifically the
3D-preview generator that hangs, apparently needing a session with an
active WindowServer, which this process doesn't have). The file is
recognized correctly by the system regardless (`mdls`, above), so this is
an environment limitation, not a writer defect — but the actual screenshot
the line's acceptance asks for stays a manual step for a person at this
same machine.

Everything else is closed. Checked 2026-09-10 against the repository, not
from memory: the "a flat package resolves with no Flutter SDK" rule and the
`flat-dart` job are in place (p0-09, qa-03), the substitution dictionary in
CONTRIBUTING and its examples in `proveDetectorsWork` too (qa-05),
`tool/ci.sh` reads its package list from `flatDartPackages` (doc-30, qa-04),
`flat_dart_check.sh` brings up `model_mcp --help` in a Flutter-free copy
(rel-04), names and platforms are recorded in §7 with a date (rel-01,
rel-17), the "A modeller, and the same agent driving it" track is in the
ROADMAP (rel-12). `dart format` has been silent since 2026-09-10 (qa-01):
before that day, twenty-three files had drifted.

#### Measured

Machine: a MacBook Pro, Apple M3 Pro, macOS 27.0, Dart 3.13.0 stable, a
`dart compile exe` build (`packages/flutter3d_mesh/tool/bench.dart`). Date:
2026-09-09. Re-checked on the same machine 2026-09-10: the rig numbers and
all 43 golden frames on Impeller — in the rows above. Every number is an
average across five runs after one unwarmed run.

**0.1 — the macOS rig (Metal, Impeller).** The `apps/flutter3d_modeler` app,
a release build, `--dart-define=stress=<triangles> --dart-define=objects=<draw
calls> --dart-define=orbit=600`: the camera makes a full circle over 600
frames, and the app prints and displays what the frames cost. The first ten
frames are dropped (shader compilation and the first load). The display is
120 Hz, so an "ideal" frame here is 8.33 ms, not 16.6.

| Scene | avg frame | worst frame | avg `render` | frames >16.6 ms |
|---|---|---|---|---|
| 1M triangles, 1 draw | 8.33 ms | 8.34 ms | 1.02 ms | 0 of 587 |
| 1M triangles, 200 draws | 8.36 ms | 16.67 ms | 5.41 ms | 2 of 587 |
| 1M triangles, 1000 draws | 27.11 ms | 108.33 ms | 24.87 ms | 299 of 587 |

What follows from this:

- **The p0-02 macOS threshold is met with margin to spare**: a million
  triangles in one mesh doesn't cost a frame even a sixth of its budget,
  `render` costs a millisecond. Triangles aren't what the viewport will
  bottleneck on.
- **It will bottleneck on the number of draw calls.** A thousand objects
  with the same total geometry cost 24 times as much — 24.87 ms versus
  1.02 — and half the frames run late. Two hundred pass. This number goes
  into the project profile as an object budget (`doc-13`) and explains why
  the modeler needs instancing and material-based batching before mesh
  simplification.
- A worst frame of 108 ms at a thousand objects isn't an outlier but the
  shape of the distribution: at that call count, frames come in unevenly,
  and `ExportReadiness` should warn about object count, not only
  triangles.

**0.1 and 0.5 in the browser — two answers, and one changes the plan.**

**The app doesn't start under `--wasm`.** The build succeeds
(`flutter build web --wasm`, `main.dart.wasm` — 2.3 MB), the page loads,
the tab title changes to "flutter3d modeller" — and then two minutes of a
blank white screen, with not one console message. The same revision, built
as JS (`flutter build web --profile`), draws its first frame in a few
seconds: a cube, "Open" and "Save as .f3d" buttons, an `opened in 36 ms`
line. A million triangles also draws fine under JS. Checked in Chrome on a
local server with COOP and COEP — without those headers the bootstrap
falls back to the JS build on its own, and the difference would have gone
unnoticed.

This is exactly the outcome the plan already recorded for: "doesn't work
under wasm → a JS build as ARCHITECTURE §1's own recorded exception":
**phase-1 web ships on dart2js**, and the wasm failure's cause becomes its
own separate item. The app's first version — before the file layer existed
— did draw under wasm, so the cause is something that arrived along with
it; `file_selector_web` and `path_provider` were checked as suspects and
ruled out (the first is already on `package:web`, the second never enters
the web build, being a conditional export).

**There are still no frame numbers from the browser, for a methodological
reason.** A tab nobody is looking at is throttled to one frame per second,
and keeping a Chrome window in the foreground through a scripted run
doesn't work. The web measurement is taken with the tool that already
exists for this — `packages/flutter3d_webgl/tool/profile_web.py`, which
brings up the build and drives the browser itself — and that's a separate
pass. Until then, the p0-02 row stays without a number, and §7 can't cite
it as a passed threshold.

**0.5 — files in the browser.** A custom wrapper was written over
`package:web`: an `<input type="file">` for opening and a `Blob` +
`<a download>` for saving
(`apps/flutter3d_modeler/lib/src/files/project_files_web.dart`), with
`file_selector` for the native half. Both halves pass analysis, the JS
build with the buttons runs; a live run of "open a GLB → a frame → download
a `.f3d`" in three browsers stays a manual step alongside the frame
numbers.

**0.2 — the `EditMesh` spike (a half-edge mesh over `Int32List`, an
operation rebuilds the arrays wholesale).**

| What | 25k quads (50k triangles) | 100k quads (200k triangles) |
|---|---|---|
| `EditMesh.fromFaces` | 8.4 ms (336 ns/face) | 33.1 ms (331 ns/face) |
| `toMeshData` | 17.7 ms (710 ns/face) | 59.2 ms (593 ns/face) |
| `signedVolume` | 13.4 ms | 37.1 ms |
| `validate` | 3.3 ms (131 ns/face) | 15.4 ms (154 ns/face) |

`extrudeFace` a thousand times in a row from a cube (growing to 4004
faces): **1010 ms for a thousand operations**, roughly a millisecond per
operation, growing with the mesh's size.

What follows from this, against thresholds p0-04 and p0-11 of the plan:

- **A full rebuild doesn't fit in a frame.** 59 ms for `toMeshData` at
  200,000 triangles is above the 33 ms budget, and an operation with a full
  array rebuild costs about the same again. A half-edge structure with
  in-place editing (`mesh-11`) and `writePositions(into:)` (`mesh-14`)
  isn't an optimization — it's a condition for interactivity.
- **The structure itself is cheap.** `validate` walks every half-edge at
  154 ns per face, and building it costs 331 ns: traversal and linking
  aren't the bottleneck — rebuilding `MeshData` and allocating a `Vector3`
  per vertex in the spike is. That's exactly what `mesh-14`
  ("hash-free filling") targets.
- **The "≤8 ms → an in-frame rebuild" threshold only holds up to roughly
  25,000 triangles.** A full rebuild is acceptable as a fallback for phase
  1's small primitives, not for an imported model.

The `mesh-spike-extrude.png` frame hasn't been captured yet: it needs
`flutter3d_testing`, meaning an app or a package with the Flutter SDK, and
gets captured alongside `view-02`.

**0.2a — phase-1 measurements (`mesh-31`), the same rig, dated
2026-09-10.** Taken against the whole working code: `EditMesh` with a log,
per-corner normals, ear-clipping triangulation, corner-to-GPU-vertex
merging, tangents, a picking tree.

| What | 25k quads (50k triangles) | 100k quads (200k triangles) |
|---|---|---|
| `EditMesh.fromFaces` | 20.3 ms (814 ns/face) | 97.0 ms (971 ns/face) |
| `importMeshData` | 101.4 ms | 512.9 ms |
| full `toMeshData` | 27.2 ms | 101.7 ms |
| `MeshLayoutPlan.build` | 18.4 ms (735 ns/face) | 69.7 ms (698 ns/face) |
| `fillVertices` every row | 1.73 ms (70 ns/face) | 6.73 ms (67 ns/face) |
| `fillVerticesOf` 40 vertices | 2.2 μs | 1.5 μs |
| `MeshBvh.rebuild` | 13.2 ms | 54.7 ms |
| `MeshBvh.refit` | 1.19 ms | 5.00 ms |
| `MeshBvh.raycast` | 0.5 μs | 0.5 μs |
| a history step over 1% of vertices | 42 μs | 172 μs |
| `signedVolume` | 2.45 ms | 10.2 ms |
| `validate` | 0.55 ms (22 ns/face) | 2.15 ms (22 ns/face) |

Separately, on a shape where the operation repeats: `loopCut` ×256 over a
32-segment cylinder — **17.2 ms**; `extrudeFace` ×1000 from a cube —
**691 ms**, meaning 0.7 ms per operation, growing with the mesh's size
(this shape is left over from the spike and still rebuilds arrays wholesale;
`extrudeFaces` from `mesh-23` edits in place).

What follows from this:

- **The p0-04 threshold is closed.** A full conversion of 200,000
  triangles is 101.7 ms, and almost all of it (69.7) is decisions:
  triangulation, normals, corner merging. Filling rows from an already-built
  plan costs 6.7 ms, and rewriting the rows of forty dragged vertices costs
  1.5 μs — 45,000 times cheaper than a full conversion. Dragging a
  million-triangle mesh bottlenecks on the buffer upload (p0-06, 5.39 ms),
  not data preparation.
- **The `refit = rebuild` threshold from mesh-20 is met:** 5.0 ms versus
  54.7 — eleven times cheaper and inside the 5 ms p0-10 named as the
  condition for dragging at 200,000. A ray is half a microsecond, meaning a
  click on a face is free even on every mouse move: p0-10 is confirmed on
  working code, picking stays on the CPU.
- **A history step over 1% of vertices is 172 μs at 200,000**, confirming
  p0-05's choice on working code: a log of prior values, not chunk copying.
- **`toMeshData` grew from 59 ms in the spike to 102, and this isn't a
  regression.** The spike gave every corner the face normal; now normals
  are computed per corner with sharp/angle/smooth splitting, corners merge
  into shared GPU vertices, and `mesh-17` added tangents, without which a
  model under a normal map goes black. Paid once when rebuilding the plan,
  not in the frame.
- **Import was quadratic, and the measurement found this.** Before the fix,
  `importMeshData` took 6.6 s at 50,000 triangles: an edge key of the shape
  `a·2³² + b` carries only `b` in its low bits, so a set of 150,000 such
  keys puts every edge sharing an endpoint into the same bucket. The key is
  now packed by vertex count — 101 ms at 50,000, 513 ms at 200,000, and
  linear again.
- **`validate` and `signedVolume` got an order of magnitude cheaper**
  compared to the spike (15.4 → 2.15 and 37.1 → 10.2 ms) — allocation-free
  walks per element.
- **`fromFaces` is three times more expensive than the spike** (33 → 97
  ms). The builder keeps a hash of vertex pairs, and nine logged arrays
  were added on top. This is the cost of opening a file, paid once; if
  import becomes noticeable, this is where to trim.

**0.2b — a mesh through an isolate (`mesh-30`), the same rig, dated
2026-09-10.** `packages/flutter3d_mesh/tool/bench_isolate.dart`, a 316×316
grid.

| What | 200k triangles |
|---|---|
| `EditMesh.toBytes` | 2.7 ms |
| `EditMesh.fromBytes` | 2.5 ms |
| round trip through `Isolate.run` | 11.4 ms |
| of which, the transfer itself | 0.9 ms |

- **A mesh crosses into an isolate in 11 ms at 200,000 triangles**, and
  almost all of it is writing and reading bytes. The actual transfer
  through `TransferableTypedData` costs 0.9 ms: the buffer moves rather
  than being copied. This confirms p0-07's decision on a working format —
  a long operation can be moved into an isolate for a few percent overhead
  of the operation itself.
- Chunking gives the same order of magnitude: 32 chunks give a worst case
  of 0.8 ms out of a 15.6 ms total. On the web, where there are no
  isolates, this is the path (`ui-34d`).


**0.3 / p0-05 — what to pay for a history step.**
`packages/flutter3d_mesh/tool/bench_persistence.dart`, 200,000 vertices
(positions — 2344 KB), a 1% edit per step, seed 1234. A full copy, for
scale, is 0.18–0.25 ms.

| Structure | clustered: bytes/step | clustered: time | scattered: bytes/step | scattered: time |
|---|---|---|---|---|
| CoW chunks, 256 | 24 KB (1.0%) | 0.17 ms | 2162 KB (92.2%) | 0.37 ms |
| CoW chunks, 1024 | 28 KB (1.2%) | 0.07 ms | 2344 KB (100%) | 0.37 ms |
| CoW chunks, 4096 | 48 KB (2.0%) | 0.09 ms | 2352 KB (100.4%) | 0.31 ms |
| flat array + a log of prior values | 46.9 KB (2.0%) | 0.05 ms | 46.9 KB (2.0%) | 0.04 ms |

**Chunking doesn't meet the p0-05 threshold, and a log does.** The rule was
recorded as: "≤10% of a copy and ≤2 ms under both distributions → a chunk
is chosen; clustered-only → a flat array + a log." Chunks of any size cost
92–100% of a full copy under a scattered edit — a thousand random vertices
touch nearly every chunk, and copy-on-write copies the whole mesh. A log of
prior values costs 2% in both cases and takes 1.5 to 9 times less time.

What this changes in the plan:

- `mesh-10` writes, **not** a `PersistentFloat32Vector` with chunks, but a
  flat `Float32List` plus a `(indices, prior values)` log per step. Chunks
  stay in the plan text as a rejected option, with this measurement as the
  reason.
- The `doc-31d` acceptance ("untouched chunks stay `identical` after
  opening a file") gets rewritten: a log has no versioned values, the old
  state exists only through rollback. In the project file, history is the
  same log entries, not references to shared blobs.
- `mesh-30` (transfer to an isolate) simplifies: one array plus a log needs
  transferring, not a graph of shared chunks.

**p0-10 — picking on the CPU.**
`packages/flutter3d_geometry/tool/bench_bvh.dart`, spheres of the given
size, 10,000 rays from random points toward the model's center, seed
20260909.

| Triangles | build | refit | ray via tree | ray by brute force | how many times |
|---|---|---|---|---|---|
| 49,728 | 14.2 ms | 1.3 ms | 2.2 μs | 1.19 ms | 534× |
| 198,468 | 60.9 ms | 6.0 ms | 2.9 μs | 4.70 ms | 1618× |
| 998,000 | 320.3 ms | 27.3 ms | 3.8 μs | 23.42 ms | 6193× |

**The threshold is met with enormous margin: picking stays on the CPU**,
and neither a face id pass nor a half-edge neighborhood search is needed
in phase 2. A ray is a few microseconds against a one-millisecond
threshold.

Two numbers weren't right on the first attempt, and it's worth recording
this: the first version of `TriangleBvh` sorted each node's range with a
comparator that recomputed the centroid every time, and built a tree over a
million triangles in **3.1 seconds** against a 100 ms threshold; `refit`
recomputed every node from its triangles and cost 43 ms at 200,000 against
`mesh-20`'s 5 ms requirement. Neither number is a property of the
approach, but of the implementation: the median is taken by quickselect
over precomputed centroids, the split axis is chosen from the centroids'
own spread (three floats per triangle instead of nine), an internal node's
box is the union of its children's boxes, and `refit` runs bottom-up.
After this, a build at 200,000 is 61 ms, refit is 6 ms.

**p0-07 — where to run a long operation.**
`packages/flutter3d_mesh/tool/bench_isolate.dart`, a 316×316 grid (99,856
quads, 199,712 triangles), building plus `toMeshData`.

| Approach | time | overhead |
|---|---|---|
| on the calling isolate | 81.6 ms | — |
| via `Isolate.run` | 78.3 ms | within noise |
| `Isolate.run` + `TransferableTypedData` | 78.8 ms | within noise |
| chunked, 8 chunks, yielding | 68.1 ms | worst chunk 12.0 ms |
| chunked, 32 chunks, yielding | 64.4 ms | worst chunk 2.1 ms |

**Both thresholds are met, and this is the rare case where there's no need
to choose.** An isolate on native costs less than measurement noise (the
threshold was "≤20% or ≤50 ms"), and slicing into 32 chunks gives a worst
chunk of 2 ms against a 50 ms threshold. So: operations are written
step-based from day one — what the web needs, since it has no isolates —
and on native, the same work, when desired, moves into `Isolate.run`
almost for free.

**A web measurement, finally taken rather than deferred.** Real headless
Chrome (`--headless=new`), not an assumption:

| Operation | Approach | time |
|---|---|---|
| export 200k (the same 316×316 grid) | `dart compile js` | 353.5 ms |
| export 200k (the same 316×316 grid) | `dart compile wasm` | 427.4 ms |
| import 30 MB (a real `.glb`, 625,681 vertices, 1,248,200 triangles, built by `GltfWriter`, checked by its own round trip) | `dart compile js`, `GltfLoader().load()` via `fetch` | ≈10 ms |

Both reference operations sit two orders of magnitude below `ui-34d`'s own
one-second threshold. `ui-34d` (a web worker) doesn't get built: the
"p0-07/p0-08 show a freeze longer than 1 s" condition didn't fire for
either operation.

**p0-06 and p0-11 — the whole edit path, every frame.** The rig — the same
app, `--dart-define=churn=true`: 1% of the vertices move, `MeshData` is
rebuilt, `DeviceMesh.upload` uploads it, the frame draws. 600 frames, the
first ten dropped.

| Scene | edit | rebuild | upload | avg frame | worst frame | frames >16.6 ms |
|---|---|---|---|---|---|---|
| 200k triangles | 0.05 ms | 0.52 ms | 1.24 ms | 8.33 ms | 8.33 ms | 0 of 587 |
| 1M triangles | 0.19 ms | 2.35 ms | 5.39 ms | 9.33 ms | 25.00 ms | 68 of 587 |

- **p0-06: `DeviceMesh.upload` fits inside a frame, so
  `overwriteGeometry` moves to phase 4.** The threshold was "≤16.6 ms →
  overwrite moves to phase 4": 1.24 ms at 200k and 5.39 ms at a million.
  `view-14` (partial buffer rewrite, a four-backend change plus a
  conformance check) **doesn't enter phase 1** — a saved M-sized item and
  one fewer engine change out of forty-six.
- **p0-11 at 200k is the first outcome for the threshold**: no pauses at
  all, zero slow frames, the whole pipeline is 1.8 ms. The API stays
  value-based, a snapshot per command, with no mutable working mode.
- **At a million, the second outcome**: 12% of frames run late, the worst
  at 25 ms. Meshes this size need `toMeshData(into:)` from `mesh-14`
  (reusing a buffer instead of rebuilding it) and a snapshot per
  transaction rather than per command. This is already a recorded phase-1
  item, and now it has the number that triggers it.

**anim-31 — a character pose.**
`packages/flutter3d/test/skeleton_posing_test.dart`: `Skeleton.update`
across 64 bones with a new pose each time — **17.5 μs per pose** (273 ns
per bone). A hundred characters in a frame — 1.75 ms, meaning FK isn't
phase 3's bottleneck.

The number was taken by a test, not an AOT bench, and that's part of the
answer: `Skeleton` pulls in `SceneNode` → `Scene` →
`flutter3d_hardware` → the Flutter SDK, so `dart compile exe` never reaches
it. It's therefore not comparable to `ARCHITECTURE.md` §14's own table; to
become comparable, posing would have to stop walking the scene graph —
that's `anim-02`, not this measurement.

**p0-13n — what the macOS sandbox permits writing.** An app with the
sandbox on (`com.apple.security.app-sandbox`, as `flutter create` sets it
up), a release build, `--dart-define=sandbox=true`; the probe —
`apps/flutter3d_modeler/lib/src/files/sandbox_probe.dart`.

| Where | direct write | temp file + rename |
|---|---|---|
| the container (`getApplicationSupportDirectory`) | yes | yes |
| "the home directory" | yes — because `HOME` is redirected | — |

`HOME` inside the sandbox is
`~/Library/Containers/dev.flutter3d.modeler/Data`, meaning the sandbox is
genuinely on, and the process's own "home directory" is its own container.

Two conclusions follow:

- **Autosave (`ui-18`) and crash recovery work with no caveats**: inside the
  container, both a direct write and an atomic rename-based write are
  permitted. This is the place where losing work isn't acceptable, and it's
  fully available.
- **A file chosen by a human isn't checked by the probe**: access is
  granted alongside the panel, and there's no way to open it without a
  human (a scripted Return keypress on a sleeping screen did nothing). The
  remaining step is manual, a minute long: build `flutter run -d macos
  --release --dart-define=sandbox=true --dart-define=sandboxPick=true`,
  choose a name in the panel, and read the line — the app prints both
  whether the file was written and whether a `temp file + rename` would
  have worked alongside it. Per Apple's own documentation the second one
  doesn't pass: `user-selected.read-write` grants access to the chosen
  file, not to its directory — which is why `saveAs` in
  `project_files_io.dart` writes directly to the chosen path and explains
  in a comment why it isn't done via a temp file. The result line needs to
  be added here after the manual run.

**pro-sc-01 — a stroke at 1.2 million triangles.**
`packages/flutter3d/test/sculpt_budget_benchmark_test.dart`, the same class
of machine as the measurements above (a MacBook Pro, Apple M3 Pro, macOS
27.0), but `flutter test` (JIT), not `dart compile exe`:
`DeviceMesh`/`GraphicsDevice` name the Flutter SDK, so AOT is unreachable
for them — the same boundary `pro-rn-01`'s own bench has. Date: 2026-09-13.
A 775×775 grid (1,201,250 triangles, 602,176 vertices, every face marked
smooth) — the same generator as `tool/bench.dart`'s `grid`, with one fix:
without `FaceFlags.smooth`, `EditMesh` doesn't merge corners into shared
GPU vertices, and the vertex buffer comes out four times larger
(153.76 MB instead of 38.54 MB) — the first number this bench printed
before the fix is left in its own doc comment as an explanation, not as a
measurement. Every number below is across five runs in a row, with no
worst-run dropped: the spread on this shared machine under JIT turned out
to be noticeable (see below), and dropping it would have meant deciding for
the reader what counted as an outlier.

Once, opening and preparation (the plan line about "3 s"):

| What | Time across five runs |
|---|---|
| `EditMesh.fromFaces` (775×775, smooth) | 1.7–2.9 s |
| `MeshLayoutPlan.build` (corner merge, face splitting, normals) | 0.8–1.3 s |
| `fillVertices` (every row) | 30–90 ms |
| `withGeneratedTangents` (once, not part of a stroke) | 0.25–0.43 s |
| `DeviceMesh.upload`, the CPU backend as a byte-copy proxy | 16–33 ms |
| `TriangleBvh.fromMesh` | 0.68–1.08 s |
| **total** | **3.3–5.7 s — the 3 s threshold is not met on any of the five runs** |

The vertex buffer is 38,539,264 bytes (38.54 MB), matching the plan's
"38 MB" line to within a percent.

Per stroke, repeated (the plan line about "8/16 ms"), averaged across three
timed iterations after one untimed one, a new random center each time, a
circle of radius 0.1028 in the grid's own coordinate system — ~19,948
vertices:

| What | Time across five runs |
|---|---|
| selecting ~20k vertices inside the circle (a linear pass over 602k) | 27–121 ms |
| `moveVertex` × the selected vertices, into the log | 6–17 ms |
| `MeshNormals.build` (the whole mesh — there is no partial path) | 255–824 ms |
| `fillVerticesOf` (only the affected rows) | 1.8–5.3 ms |
| `DeviceMesh.overwriteVertices`, the CPU backend | 1.9–35 ms |
| one `TriangleBvh.raycast` | 41 μs — 1.7 ms |
| **the whole stroke** | **294–1005 ms — the 8 and 16 ms thresholds are not met on any of the five runs, missed by 20–60×** |

**Re-measured 2026-09-17, with the partial normal path this table said did
not exist.** `MeshNormals.rebuildAround` now rebuilds the fans at the moved
vertices and at the ring of faces around them, and the benchmark calls it
where it used to call `build`. Both numbers below were taken back to back in
one sitting on the same machine, the only difference being which of the two
the stroke calls:

| | normals | the whole stroke |
|---|---|---|
| `MeshNormals.build`, the whole mesh | 156.70 ms | 178.81 ms |
| `MeshNormals.rebuildAround`, the ring | 17.4–18.6 ms | 38.2–41.1 ms |

Eight times on the normals, four on the stroke — and the stroke still misses
16 ms. The picture that number paints has changed, though, and it is the part
worth carrying forward: **normals are no longer *the* bottleneck, they are
one of two of roughly equal size.** Selecting the touched vertices is a
brute-force scan over all 602,176 of them (15.1 ms) and is now as expensive
as the normals it feeds; the ring rebuild is 17.4 ms because a brush this
wide touches tens of thousands of vertices and `rebuildAround` gathers them
into hash sets. The first wants the spatial chunking `pro-sc-02` describes —
which is what this row already concluded, for a different reason — and the
second wants an index rather than a set.

Setup is unchanged at 1.87 s and now **passes** its own 3 s threshold, which
the first run did not: nothing about it was touched, so the difference is
this machine under a lighter load than the day the 3.3–5.7 s spread was
taken. That is the honest reading of a spread that wide, and the reason the
paired measurement above was taken in one sitting rather than compared
across dates.

Chrome, the same day, the same way: a stroke went from 7.58–7.71 s to
**396.87 ms**, nineteen times, and setup stayed at 24.87 s. Both still miss.

The spread between runs (in places more than 2×) isn't measurement noise at
the fractional-microsecond level — it's the load of a shared sandbox:
`flutter test` under JIT on a machine not dedicated to measurement, not a
`dart compile exe` run the way the rest of §6 was taken. The conclusion's
direction — both thresholds missed — doesn't change on any of the five
runs.

What follows from this:

- **The "3 s" threshold is not met.** The main contributors are
  `MeshLayoutPlan.build` and `TriangleBvh.fromMesh`, both linear in
  triangle count and already, on their own, taking a noticeable fraction of
  a second at 1.2 million.
  
- **The "8/16 ms" threshold is missed by one and a half to two orders of
  magnitude, and the cause is neither selection, nor overwrite, nor
  raycast, but `MeshNormals.build`.** This is the only normal-recompute
  path that exists today, and it always walks the whole mesh: 255–824 ms
  for a stroke touching 20,000 out of 602,000 vertices. `mesh-31`'s own
  conclusion ("normals are recomputed on every frame while someone drags a
  vertex") holds at 200,000 and stops being cheap at 1.2 million precisely
  because there is no partial normal recompute. **Superseded 2026-09-17**:
  there is one now, the stroke is four times cheaper, and the threshold is
  still missed — see the paired table above. The sentence is kept rather
  than rewritten because it is what the row concluded on the evidence it
  had, and the partial path was built because of it.
- **`overwriteVertices` rewrites not what was touched, but a band around
  it.** The ~20,000 touched vertices sit in GPU rows whose minimum and
  maximum numbers together span ~123,000 rows (7.9 MB) — because, with a
  flat, unchunked vertex layout, a circular stroke touches whole grid
  bands, not a compact range. This is exactly what `SculptMesh` chunking
  (`pro-sc-02`) is meant to fix.
- **Garbage per stroke is a code-reading conclusion, not a traced
  number.** `MeshNormals` and `MeshLayoutPlan` keep their buffers between
  calls and don't reallocate them unless the mesh grows (`_resize` only
  ever grows a buffer); vertex selection writes into a pre-allocated
  `Int32List`, not a fresh list every stroke; and a third stroke isn't more
  expensive than the first (e.g. 309.97 ms versus 298.98 ms in one run) —
  if every stroke reallocated memory for normals or for the selected-vertex
  list, a third stroke usually wouldn't come out cheaper than the first.
  Dart has no portable allocation counter without `--observe` + DevTools,
  which there's nowhere to bring up in this sandbox, so this is a
  source-reading conclusion and an indirect check, not a separately taken
  number. What follows from it: today's cost of a stroke at 1.2 million is
  time (the whole mesh is recomputed), not garbage (buffers are already
  reused).
- **Chrome was measured the same day, with the same `flutter test`.** The
  reason a browser supposedly needs `profile_web.py` and a foregrounded tab
  — true for `p0-02`'s own `requestAnimationFrame`-based measurement —
  doesn't apply here: this test never asks for a frame, so `flutter test
  --platform chrome` runs it entirely headless, like any other platform.
  Three runs on this same machine: opening+BVH — 24.2–24.4 s (the 3 s
  threshold not met), a full stroke — 7.58–7.71 s (the 8/16 ms thresholds
  not met). Chrome is roughly 4–5× slower than the native run on the same
  arithmetic — the cost of JS/wasm with no SIMD path, not something
  specific to sculpting. **The Galaxy A55 still hasn't been measured** —
  needs a phone in hand, same as `p0-03`.
- **Which threshold applies to what, since the plan's own line doesn't say
  directly.** Opening and building the BVH are a one-time cost at model
  load, and that's what the same "3 s" measures, the way `p0-02` measured
  loading separately from a frame; selection, editing, normals, overwrite,
  and one raycast repeat on every mouse move during a stroke, and that's
  what should fit inside the "8/16 ms" frame budget — by analogy with
  `p0-02`'s own distinction between a 120 Hz frame (8.33 ms) and a 60 Hz
  one (16.6 ms). The "frame" from the plan's line isn't re-measured here:
  `p0-02` already measured a real Metal/Impeller frame with a
  million-triangle mesh in one draw call on this same machine (8.33 ms
  average, 0 of 587 frames over 16.6 ms) — 1.2 million doesn't change that
  conclusion, since `p0-02` already showed a frame bottlenecks on draw-call
  count, not triangle count.
- **Upload and overwrite were measured through `CpuDevice`, not
  Impeller.** `CpuDevice.uploadGeometry`/`overwriteGeometry` do exactly the
  half of a real backend's work that moves bytes (`Uint8List.fromList`,
  `Uint8List.setAll`) and nothing further — no driver call, no command
  buffer, no GPU. The numbers above are a proxy for memory-copy cost, not a
  repeat of `p0-06`'s own measurement on real Impeller (1.24 ms at 200,000
  triangles, 5.39 ms at 1 million) — that measurement is the one to trust
  for the GPU side.
- **A `pro-sc-09` decision:** the web (Chrome, wasm/JS) wasn't measured
  directly, but since even the native macOS path misses 8/16 ms on a
  stroke touching 20,000 of 1.2 million vertices, and Dart on the web isn't
  faster than native, the web's stroke-density limit (`pro-sc-09`) should
  be based on whatever mesh size lets this same path fit its budget —
  meaning noticeably smaller than 1.2 million, until `pro-sc-02` replaces
  the full normal recompute with a chunked, local one. **Still the
  decision after the 2026-09-17 re-measurement, with the reasoning
  narrowed**: a stroke on macOS is 38 ms against 16, which is a factor of
  2.4 rather than 20–60, so the size that fits is much closer to 1.2
  million than the first run suggested — and the two costs that remain
  scale differently, one with the mesh (the selection scan) and one with
  the brush (the ring). A limit chosen on the old numbers would be far too
  small; one chosen on these should be measured at the size, not
  extrapolated from this one.

### Phase 1 — the first version

| # | What | Package | Size | Depends on |
|---|---|---|---|---|
| 1.1 | Design the two undrawn screens: import with checks, export with checks | design | S | — |
| 1.2 | `EditMesh` in full: the structure, `from/toMeshData`, persistence, corner attributes | mesh | L | 0.2, 0.3 |
| 1.3 | Selection: vertices/edges/faces, loop, ring, grow; a BVH for CPU picking | mesh | M | 1.2 |
| 1.4 | Phase-1 operations (§5.2's table) with a test for each | mesh | L | 1.2 |
| 1.5 | Checks: n-gons, manifoldness, normals | mesh | S | 1.2 |
| 1.6 | Parametric objects: primitives, a lathe over `LatheShape` | mesh | S | 1.2 |
| 1.7 | `ModelProject`, commands, history, transactions, project serialization | model_core | L | 1.2 |
| 1.8 | `ExportReadiness` and `ProjectProfile` | model_core | S | 1.7 |
| 1.9 | `GltfWriter`, `ObjWriter`, `StlLoader` with round-trip tests | formats | M | step 1, §8 (doc-01) |
| 1.10 | Vertex/edge overlays, a golden frame | flutter3d | S | — |
| 1.11 | The shell: theme, framework, three layouts, "Object" and "Mesh" modes | app | L | 1.7 |
| 1.12 | The viewport: orbiting, object and sub-element picking, an XYZ manipulator | app | M | 1.3, 1.10 |
| 1.12a | Basic operations in full: a modal transform with axis constraint, numeric input, and snapping (view-23n), a selection box and selection commands (view-24n, doc-32n), a pivot point and space (doc-33n), gizmo handles through the same path (view-25n) | app + core | M | 1.12 |
| 1.13 | The last-operation card with reapplication | app | S | 1.7, 1.11 |
| 1.14 | A modal lathe screen with a profile editor | app | M | 1.6 |
| 1.15 | Import and export with check dialogs; disk on desktop and web | app | M | 1.1, 1.8, 1.9 |
| 1.16 | Autosave and recovery | app | S | 1.7 |
| 1.17 | The MCP server: commands as a tool table, an "agent builds a table" scenario in CI | model_mcp | M | 1.7 |
| 1.18 | App tests through `flutter3d_cpu` (picking, dragging, a frame) and syncing numbers into the README/site | app | M | everything |

The critical path: 1.2 → 1.4 → 1.7 → 1.11 → 1.15. Format writers (1.9) and
overlays (1.10) don't depend on it and can start on day one — these are the
first tracks handed to agents under pre-written tests (plan §4.2–4.3); one
executor.

---

## 7. Decisions needed before starting

The recommendation column was replaced 2026-09-09 with the owner's own
decisions (Dmitrii); each is final and entered into the plan as fact. Two
questions from the design plan — monetization and timelines — aren't
repeated here: they aren't engineering questions.

| Question | Options | Decision, 2026-09-09 |
|---|---|---|
| Where the code lives | this monorepo / a separate one | **here.** The packages join the workspace, the structure scanner, CI, and the publishing order; the cost is a longer CI and the "document numbers match the tree" rule covering five more packages |
| Node graph | shader-based / a texture compositor / none | **a texture compositor with a fixed node set** (§4.1); the ROADMAP gets reworded at the September 28 review, and the design gets renamed |
| Undo for meshes | snapshots / inverse commands / persistent values | **persistent values with structural sharing** (§4.3) |
| Project format | its own / glTF with extensions | **its own `.f3dproj` with history**, sectioned following `.f3d`'s pattern: the history section references chunks that already sit in the file as blobs, the history limit applies to the file, "save without history" is an option, the command journal stays; acceptance — save → open → undo three steps; glTF stays output-only |
| Web at the start | equal footing / view-only | **an equal-footing platform from the first version.** Measurements 0.1 and 0.5 stay quality gates: if a threshold isn't met, phase 1 includes whatever's needed to meet it (a JS build as a recorded exception, chunks instead of an isolate, a web worker for a freeze longer than a second) |
| Phase-1 platforms | macOS / plus web / plus mobile | **all four: macOS, web, Android (tablet and phone), iOS (iPad and iPhone).** Layouts, pen, touch, and platform configuration are phase 1; a physical iPad and an Apple Developer account by mid-phase-1; macOS signing via "right-click → Open" |
| Interface language | Russian / plus English | **Russian and English from the first version**; the core, MCP, and `says` stay in English |
| Boolean operations | homemade / a BSP port | **a BSP-approach port** in phase 2, with an honest warning about coplanar faces (unchanged) |
| What to do with screen 12's "Render" | a path tracer / a snapshot via the software rasterizer | **a snapshot from the same renderer** with supersampling and frame-graph passes; a path tracer is out of scope |
| "Scene" mode | light/environment/shadows/post / plus placing assets | **plus placing several assets** (phase 2): importing into an existing project and exporting a scene as one GLB |
| Screen-11 simulations | extend `flutter3d_physics` / a separate solver | **a separate `flutter3d_cloth` solver, phase 4** |
| The engine's vocabulary | take it from `flutter3d` / one pure package / two | **two packages: `flutter3d_geometry` and `flutter3d_formats`** (§5.1) |
| FBX | its own reader / server-side conversion | **its own reader in Dart** — a `flutter3d_fbx` package over `flutter3d_formats`, phase 2, as a separate track once phase 1 is in users' hands; no server-side conversion |
| Export on a check failure | refuse / warn | **warn, and export with explicit confirmation**; refuse only on empty geometry |
| Hotkeys | homemade / Blender-like | **Blender-like** |
| Icons | Material Symbols (an external package) / the SDK's `Icons` | **the SDK's `Icons`**, with a mapping table |
| Sculpting | dynamic topology / multiresolution | **multiresolution**; screen 08 gets a "Subdivide" button instead of a "density" one |
| Non-manifold input | a radial structure / split on import | **split on import** and show it as an issue |
| Checking export in an external engine | a manual checklist / an automated test | **headless Godot in CI** plus a manual Unity/Blender checklist before release |
| Team | one / two / three | **one person with agents**; the phase-1 calendar is the sum of item sizes (plan §4.3) |
| First release | December 27 / once phase 1 is in hand | **once phase 1 is in the hands of its first users**; December 27 is not the target |
| Where Play runs | in process / a companion command in `tool/` | **in process, decided 2026-09-16 by `ux-50`'s spike.** Both macOS entitlements files turn the sandbox on and the Flutter SDK sits outside the container, so a sandboxed build cannot start `flutter run --machine` at all, and the web build cannot start a process of any kind: the companion command would work on one of four platforms and only from a developer checkout. In process it is the same renderer, device and uploaded textures as the viewport everywhere the modeller opens, and "reload" is the `SceneSync` the document already runs rather than a process to restart. What it gives up is the game's own Dart — Play runs a template, not a project — which is what the companion command is still for when somebody asks for it. It does not depend on `flutter3d_game`: that package brings `pointer_lock`, `pad_input`, `flutter3d_audio` and `flutter3d_particles`, two of them native plugins, into an application that has to keep building for the web, and what Play needs from it is a walking body `flutter3d_physics` already provides |
| Name | `flutter3d_modeler` / `flutter3d_studio` / … | `flutter3d_modeler`; not reserved on pub.dev, recheck before publishing. Free as of 2026-09-09: `flutter3d_geometry`, `flutter3d_formats`, `flutter3d_mesh`, `flutter3d_model_core`, `flutter3d_model_mcp`, `flutter3d_modeler`, `flutter3d_fbx`, `flutter3d_cloth`; the app's bundle id — `dev.flutter3d.modeler` |

---

## 8. First steps

Updated 2026-09-09: §4 and §7 are now settled by owner decisions, and the
first step from the earlier list is removed.

1. ~~Split the vocabulary out of `flutter3d` into `flutter3d_geometry` and
   `flutter3d_formats` (§5.1)~~ — **done 2026-09-09**, two weeks ahead of
   schedule. `flutter3d` re-exports both, games and demos noticed nothing
   about the move, 4340 tests green. What lives where: in `geometry` —
   `MeshData`, `VertexLayout`, shape generators, tangents, morph targets,
   `Ray`; in `formats` — `ModelDocument`, materials, `LightingModel`,
   `AnimationClip`/`Track`/`Mask`, glTF/OBJ/`.f3d`/`.fmat` decoders, and the
   synchronous half of loading. What stayed in the engine: `DeviceMesh`, the
   isolate loader with `kIsWeb`, two asset sources (the Flutter bundle and
   `dart:io`), bundle resolvers, and everything that names
   `GraphicsDevice` — including KTX2, whose formats belong to the HAL.
2. Draw the two missing phase-1 screens (import with checks, export with
   checks). The handoff README itself requires this before the phase
   starts.
3. All of phase 0, by 2026-10-05: threshold-based measurements, with the
   result being numbers in this document instead of estimates. Web and
   mobile are measured as quality gates, not as a choice: phase 1 ships on
   macOS, web, Android, and iOS at once, and an unmet threshold becomes a
   phase-1 item, not a reason to drop the platform. A physical iPad and an
   Apple Developer account, by mid-phase-1.
4. `GltfWriter` with round-trip tests on Khronos models — an item that can
   start right after step 1, and is needed under any outcome; it's also the
   first track handed to an agent under pre-written tests (plan §4.3).
5. At the September 28 ROADMAP review: a model-editor track with an
   Acceptance line, and a reworded node-graph item ("fixed set of nodes
   that bakes into texture slots").
