# 3D model editor functionality — overview

Sources: `doc/model-editor-plan.md` (317+ plan items, current version from
2026-09-09/10/11) and `doc/plan-status.json` (the actual status of every item
as of 2026-09-11). This document retells the plan in plain language by
functional area rather than by item order, so the design can be adjusted by
looking at capabilities, not a table. Plan item ids are given in parentheses,
for traceability. Within a section: ✅ Done, ⚠️ Partial (with a one-sentence
reason), ⬜ Not started. A "partial" status always means the base scenario
works and the limitation is deliberate and recorded, not forgotten.

---

## Mesh core (half-edge structure and editing operations)

Editable geometry: a half-edge mesh over typed arrays, persistent history,
selection, basic and advanced operations.

**✅ Done**
- Half-edge structure `EditMesh` with tombstones, `compact()`, Euler
  primitives, `validate()` (mesh-11)
- Persistent history through a log of prior values rather than a full copy
  (mesh-10)
- Attribute layers: position/skinning per vertex, UV/color per corner,
  sharp/seam/crease per edge, material/smoothing per face (mesh-12)
- Importing a finished mesh with seam welding, orientation repair, splitting
  non-manifold edges (mesh-13)
- Building a GPU-ready layout (triangulation, normals, vertex dedup)
  (mesh-14)
- N-gon triangulation (mesh-15), normals and their recomputation (mesh-16),
  tangents (mesh-17)
- Binary mesh serialization (mesh-18)
- Selection: levels (vertex/edge/face), loop/ring, grow/shrink, by material
  (mesh-19)
- A triangle BVH for picking (mesh-20) and picking itself (mesh-21)
- Move/rotate/scale the selection with a pivot point (mesh-22)
- Face and edge extrusion (mesh-23), loop cut (mesh-24)
- Weld by distance, dissolve edges/vertices (mesh-25)
- Delete, split into objects, duplicate (mesh-26)
- Mesh diagnostics: n-gons, non-manifold edges, degenerate faces, Euler
  characteristic (mesh-27)
- Parametric primitives (cube/plane/cylinder/sphere/torus/loft) with quad
  topology ready for editing (mesh-28, mesh-29)
- The mesh runs correctly inside a separate isolate (mesh-30)
- Performance measurements and fuzzing (500 random operations × 3 seeds) for
  invariant stability (mesh-31, mesh-32)
- Golden frames of basic operations (extrusion, loop cut, loft,
  sharp-vs-smooth) (mesh-33)
- Filling holes, splitting non-manifold edges, flipping inverted shells — a
  "repair," not just a diagnosis (mesh-81n)

**⬜ Not started**
- Skinning weights as a mesh operation — accumulate, prune, renormalize
  (mesh-60), storing multiple shape keys (mesh-61, mesh-62)
- Geometry simplification (decimation/QEM) (mesh-70), full UV unwrapping
  with LSCM and island packing (mesh-71)
- Sculpting: multiresolution over the mesh (mesh-72), remeshing (mesh-73)
- Generating collision shapes from a mesh — convex decomposition, boxes,
  capsules (mesh-80n)

## Modifiers (a non-destructive operation stack)

**✅ Done**
- The modifier framework: type, context, a stack memoized by the base mesh's
  own cache (mesh-40)
- Mirror with seam stitching (mesh-41), array with deterministic ids
  (mesh-42)
- Inset bevel with an angle correction (mesh-43)
- Catmull-Clark subdivision with semi-sharp creases (Pixar), bilinear UV
  across corners (mesh-45)
- Laplacian smoothing with volume preservation (HC correction) (mesh-46)
- Boolean operations (union/subtract/intersect) via a BSP tree (mesh-47)
- Stack storage on an object, cached by geometry/modifier version (mat-18),
  stack commands and JSON parsing (mat-19)

**⚠️ Partial**
- Edge and vertex bevel (mesh-44) — works on a closed selection region
  (every face touched by the bevel must be selected whole); a single flat
  cut with no segments and no profile is not implemented
- Boolean operations (mesh-47) — volume and the coplanar-case warning are
  always correct, but the reconstructed mesh is not guaranteed watertight
  (T-junctions after triangle splitting are a known property of the
  algorithm, not just this implementation)

**⬜ Not started**
- Wrapping a boolean operation as a stack modifier with an operand object
  (mesh-48) — the core (`booleanOp`) is done, no stack wrapper exists
- Phase-2 golden frames for modifiers (mesh-49)

## The project document, commands, and history

**✅ Done**
- The document model: objects, materials, images, an export profile,
  structural sharing on copy (doc-03)
- Selection and history as part of the document (doc-04)
- A unified command system (sealed, with JSON, refusal instead of
  exceptions) (doc-05)
- Object commands: primitives, transforms, renaming, parent/child, pivot
  point, baking a transform into geometry (doc-06)
- Mesh commands over a selection: transforming elements, extrusion, loop
  cut, weld, delete, split, triangulation, normal recomputation (doc-07)
- Undo/redo with transactions, `amend` for editing the last step without a
  new one (doc-08)
- The `.f3dproj` project file format: a sectioned container with alignment,
  versioning, skipping unknown sections (doc-09)
- Reading/writing a project: canonical JSON, string interning, warnings on
  corrupted data instead of a silent fallback (doc-10)
- Importing a finished model into a new project with a report (object/
  material/triangle counts, decoder warnings), a choice of units and up-axis
  (doc-11)
- Merging an imported model into an already-open project — placing several
  assets (doc-11a-n)
- The document with an export-data cache keyed by object version (doc-12)
- A project profile: triangle/bone/texture limits, triangulation and
  manifoldness requirements (doc-13)
- Export-readiness checking with a cache keyed by object version (doc-14) —
  the finished rules are detailed further below, in "Materials"
- Determining texture size from the file header with no decoder (doc-15)
- A command journal in JSON Lines with replay (doc-16)
- Pure autosave-policy functions (doc-17)
- Listing document contents (objects/materials/skeletons/clips) (doc-18)
- The MCP server and session framework (doc-19), a tool table generated from
  document commands with a completeness check (doc-20)
- An end-to-end "an agent builds a table" scenario over the real protocol
  (doc-21), reference material for the agent (skills) (doc-22)
- Format migrations with fixtures for old versions (doc-28)
- Selection commands — select all/none/invert/grow/shrink/by material — as
  full history commands, not actions bypassing it (doc-32n)
- Pivot point (median/self/cursor) and space (global/local) for rotation and
  scale; a 3D cursor (doc-33n)

**⬜ Not started**
- History as a section of the project file itself, not only a separate
  journal (doc-31d) — the domain model exists for this (doc-09 reserves a
  section), but reading/writing the section itself is not implemented or
  marked done
- Sockets/attachment points — a geometry-free object for hanging weapons,
  effects, wheels (doc-34n)
- Texel density as a profile field and a check rule (doc-35n)
- Skeleton, clip and morph-target commands on the document (doc-26, doc-27 —
  absorbed into the "Animation" section)

## MCP tools for the agent

**✅ Done**
A complete first-version tool set mirroring document commands — object,
mesh, material (basic), modifier, selection, session verbs (list/select/
run/undo/redo/check/save/export/import/journal). Every new command
automatically requires its own tool — a test enforces this, so commands and
tools never drift apart.

**⬜ Not started — a whole functional track ("an agent that can see the
model")**
Today the agent edits the model blind: it gets readiness-check numbers, but
no picture. Requires separate engine groundwork (moving the remaining
Flutter dependencies out of the hardware layer and the rendering core, at
four points):
- Rendering a project to PNG with no GPU widget (mcp-05n) and a `render` MCP
  tool with ready-made angles (mcp-06n), a contact sheet from several views
  (mcp-07n), display modes — material/wireframe/normals/selection (mcp-08n)
- Composite recipes as one transaction: `cleanup()`, `makeGameReady(profile)`,
  `buildFrom(spec)`, `inspect()` (mcp-09n)
- Splitting history-step authorship between human/agent, undoing only one's
  own steps (mcp-10n), grouping an agent call into one transaction (mcp-11n)
- A full agent action journal with replay (mcp-12n)
- The same editing session reachable from the GUI over local HTTP, not only
  through the headless stdio server (mcp-13n), syncing with an open window
  (mcp-14n)
- Import/export as session verbs with a readiness gate and `force` (mcp-15n)

Materials (`listMaterials`, `setMaterialField`, `bakeTextureGraph`, light)
and animation (`autoRig`, `paintWeights`, `bakeIk`) as MCP tools — also not
started (mat-32, anim-30), since the underlying phase 2–3 material/animation
functionality itself isn't done beyond the basic set.

## Formats: import and export

**✅ Done**
- Comparing two model documents by category for round-trip tests (fmt-01),
  shared decoder test infrastructure (fmt-02)
- Authoring attributes for surfaces, mesh/document/sampler names, image URIs
  (fmt-03, fmt-04)
- A full set of texture sampler filtering parameters (fmt-05)
- The glTF/GLB writer: de-interleaving, deduping meshes/samplers/textures,
  materials with extensions (fmt-06)
- The glTF writer: skins, animations, morph targets (fmt-07)
- The OBJ + MTL writer with material-parameter approximation (fmt-08)
- Reading STL (binary and ASCII) (fmt-09)

**⬜ Not started**
- Differential golden frames "original vs. re-read export" (fmt-10),
  automatic export validation (fmt-11), a writer report with warnings
  (fmt-12)
- Exporting through an isolate to an application (fmt-13), a CLI format
  converter (fmt-14)
- Honestly skipping Draco/meshopt primitives instead of reading zeros
  (fmt-15)
- A dedicated STL writer (fmt-20)
- Passing KTX2 through the glTF writer end to end (fmt-21), an offline
  texture encoder for BC1/BC3/ETC2/ASTC (fmt-22), Basis Universal ETC1S
  (fmt-23)
- A dedicated FBX reader in Dart — geometry/materials/hierarchy (fmt-24),
  FBX skins and animation (fmt-25), the `flutter3d_fbx` package (fmt-29d)
- `extras` and `KHR_texture_transform` passed through end to end (fmt-19)
- A USDZ writer (fmt-27), light and cameras in the format's own dictionary
  (fmt-28)
- Output geometry compression for glTF — quantization,
  `EXT_meshopt_compression` (fmt-30n)

## Materials and textures

**✅ Done**
- Material as part of the project document: slots on an object, commands
  for add/remove/assign/duplicate a material, assigning a texture and
  loading an image (mat-01)
- Reading texture size and format from the file header with no decoder,
  recomputing weight for a target compression format, with a budget across
  three profiles (desktop/mobile/web) (mat-02 partial — see below, mat-28)
- Export-readiness check rules (part of mat-22): a material in transparency
  mode with no real alpha, a texture on an unsupported UV channel — both new
  rules on top of already-done checks for n-gons after a boolean operation
  and non-manifoldness after a mirror (those two were already done earlier
  as part of the basic mesh/geometry checks)

**⚠️ Partial**
- `TextureInfo` from file headers (mat-02) — done for PNG/JPEG and for
  recognized KTX2 compression formats (BC1/BC3/BC7/ETC2/ASTC 4×4); a KTX2
  format the engine's own encoder does not yet write (Basis Universal and
  the like) gives an honest weight from the file's own data, not a computed
  one
- Export-readiness rules (mat-22) — of the seven rules named in the plan,
  two new ones are done (blend with no alpha, texture UV channel ≠ 0); two
  were already done before this item, one references a format field that
  does not exist, one waits on a texture budget as a separate module
  (which, in turn, is done — mat-28), one is pushed up to the application
  level

**⬜ Not started**
- A full "Material" panel with every property and lighting setting (mat-04,
  a trimmed phase-1 version — mat-04a-n — also not started)
- Moving shared material-panel code into a separate package for the two
  editors (mat-03), texture slots with previews (mat-05), a color field
  with HSV/hex (mat-06), a compiled-material cache (mat-07)
- An external `.fmat` material file (mat-08)
- A pure-Dart image decoder for the texture graph — PNG inflate, baseline
  JPEG (mat-09n)
- A texture compositor: a fixed node graph (Image/Color/Blend/Levels/…),
  CPU baking, a graph-editing panel (mat-10, mat-11, mat-12, mat-13)
- A material studio — a separate preview scene (mat-15), HDRI environment
  from an LDR panorama (mat-16), from `.hdr` (mat-17)
- A modifier-stack panel in the UI (mat-20)
- Light and environment as part of the project: sources, shadows, exposure,
  control commands (mat-23), a "Scene" mode for placing assets (mat-24),
  visual light-source gizmos (mat-25)
- Fitting textures to a budget — downsizing, snapping to a power of two
  (mat-29)
- An offline texture encoder into compressed formats (mat-30)
- Golden frames for materials/modifiers/scene (mat-31)

## The viewport and rendering (in the app)

**✅ Done**
- The app viewport skeleton with two views (view-02), an orbit camera driven
  by mouse/touch/trackpad/pen gestures (view-03)
- A debug-geometry overlay — lines, points, ribbons, fill (view-05)
- Object selection by clicking a pixel (view-08), a triangle BVH for the ray
  (view-09), mesh-element selection — face/vertex/edge with occlusion
  handling, a selection box (view-10)
- A floor grid and a camera-orientation gizmo (view-11)
- A transform gizmo — move/rotate/scale by handle (view-12)
- Building the selection overlay for mesh-editing mode (view-13)
- Modal transforms with `G`/`R`/`S` keys, axis constraint, numeric keyboard
  input, snapping (view-23n)
- A drag selection box (view-24n — partial, see below)
- On-screen gizmos as separate objects with hover highlighting (view-25n)

**⚠️ Partial**
- The selection box (view-24n) — the underlying element-picking-inside-a-box
  mechanism was done and tested earlier (view-10), but the calling code
  (dragging the box with the mouse, adding/subtracting via Shift/Ctrl) had
  not been wired up as of the plan's last check

**⬜ Not started**
- Perspective/ortho display modes, "Material/Normals/Wireframe" chips
  (view-04)
- A depth-offset overlay shader (view-06), a full wireframe over the normal
  render (view-07)
- Partial GPU geometry rewrites for streaming edits to large meshes
  (view-14)
- Several independent viewports (view-15), a separate material-preview
  scene (view-16), an "in-game" profile with counters (view-17)
- Showing skinning weight as a gradient (view-18), a UV-unwrap panel
  (view-19)
- Three views for LOD tuning (view-20), a brush cursor with pen-pressure
  sensitivity (view-21)
- A draw-call-count test guard (view-22)
- Snapping to a vertex/edge/face during a transform (view-26n)

## The shell UI and platforms

**✅ Done**
- The app-shell spike, registered with the build system (ui-00, ui-01)
- A Material 3 theme with an explicit color scheme (ui-02)
- Application state (Cubit): modes, status, readiness, jobs (ui-03)
- The screen skeleton: a top bar, a side tool panel, a properties panel, a
  status line (ui-04)
- A single source of tool descriptions shared by every layout (ui-07)
- The site's asset list ready to show modeler frames (ui-14 — marked
  "done," though it is more of an infrastructure item for file I/O, really
  closing spikes p0-08 and p0-13n)

**⚠️ Partial**
- The "Object" panel: an object list, numeric transform fields, the
  modifier stack (ui-08) — the base list and numeric fields exist, full
  drag-and-drop stack functionality is uncertain
- A "last operation" card for editing parameters without a new history step
  (ui-09)
- A status line with mode metrics and the first readiness warning (ui-10)
- Undo/redo with hints in three layouts (ui-11)
- Blender-style hotkeys (ui-12)
- The loft profile screen — a curve editor (ui-13, listed here as "partial"
  per the plan's own data; the actual state is worth re-checking before
  continuing)
- An export screen with confirmation on warnings (ui-17)
- Autosave with debounce and a restore prompt (ui-18)

**⬜ Not started**
- Responsive layouts by screen width — tablet/phone (ui-05)
- Integrating the app viewport with gestures/picking/gizmos in one place
  (ui-06)
- A start screen with recent files (ui-15), an import screen with warnings
  and limits (ui-16)
- Parsing mouse/pen/touch input by device type (ui-19)
- macOS platform settings (sandbox, document types) and web (ui-20),
  Android and iOS builds (ui-21)
- ru/en localization (ui-22), accessibility — contrast, text size,
  semantics (ui-23)
- An unsaved-changes dialog on close (ui-24)
- A background-jobs indicator (ui-25)
- App golden frames (ui-26)
- A separate shared panel-widget package for both editors (ui-27)
- The animation timeline shell (ui-28), a sculpting-mode layout (ui-29)
- Handling uncaught exceptions with an emergency autosave (ui-30n)
- Drag-and-drop a file onto the window (ui-31n)
- Built-in help with a hotkey table (ui-32n)
- A "Save without history" flag (ui-33d)
- A web worker for heavy operations on the web — conditional, if needed
  (ui-34d)
- A full transform panel: position + rotation + scale as three field
  triplets (ui-35n)
- Opening a model from several files — `.gltf` with a neighboring `.bin`
  (ui-36n)

## Animation and rigging — an entire functional block (phase 3)

**✅ Done**
- Only a bare FK-skeleton-update performance measurement (anim-31, phase 0)
  — the sole item in this section marked done.

**⬜ Not started — the entire pipeline**
- A character pose with no scene, the base everything else is built on
  (anim-01), CPU skinning for previewing (anim-02)
- A skeleton and clips as part of the project document (anim-03), a
  keyframe table with interpolation (anim-04), auto-keying from the current
  pose (anim-05)
- A timeline screen with a bone tree and an action list (anim-07), a
  skeleton overlay and joint picking (anim-08)
- Persistent skinning weights and operations on them — painting, mirroring,
  smoothing, stretching (anim-09), a weight-paint brush (anim-10)
- A rig-readiness panel — bone-count limit exceeded, zero weights, unused
  bones (anim-13)
- Inverse kinematics — analytic two-bone and FABRIK (anim-14), binding IK
  constraints to a skeleton and baking into a clip (anim-15)
- Extracting and baking root motion (anim-16)
- Retargeting a clip onto another skeleton (anim-17), a retargeting screen
  (anim-18)
- Morph targets as shape keys with weight animation (anim-19), shape drivers
  from a joint's pose (anim-20)
- Skeleton templates (humanoid/quadruped) (anim-21), automatic
  skinning-weight assignment by distance to bones (anim-22), an automatic
  rigging screen (anim-23)
- An "in-game" budget screen — bones/triangles/textures against a profile
  (anim-24), background rigging jobs through the runner (anim-25)
- Round-tripping a rig through the `.f3d` format (anim-27), a parity test
  across three pose-sampling paths (anim-28)
- Skeleton-editing commands — add/remove/rename a joint, recomputing inverse
  binding (anim-29)
- Animation MCP tools: `autoRig`, `paintWeights`, `bakeIk`, `retargetClip`
  and others (anim-30)
- Phase-3 startup performance measurements (anim-31a-n)
- Hard influence/bone-count limits with a refusal message (anim-32)
- Inverse kinematics for posing — separate from rigging, for manual pose
  touch-up (anim-31n)

## Professional modes — an entire functional block (phase 4)

**⬜ Not started — nothing**
The plan's least precisely scoped section (L-sized estimates could double),
but the richest in functionality:
- **UV unwrapping**: a seam flag, LSCM island unwrapping, projection
  unwrapping, a stretch metric, island packing, an unwrap screen
  (pro-uv-01…07), an atlas spanning several objects (pro-uv-08n)
- **Sculpting**: a separate mesh structure for multiresolution, brushes
  (draw/clay/smooth/…), a BVH with point-wise updates, recording a stroke
  as one history step, subdivision levels, a panel-free screen layout
  (pro-sc-01…09)
- **Simplification and LOD**: attribute-aware QEM simplification, storing
  levels on an object, three views for LOD tuning (pro-lod-01…04), impostors
  and billboards for distant LODs (pro-lod-05n)
- **Retopology**: automatic quad retopology, drawing quads over a surface,
  baking normal/AO/curvature/thickness maps, a baking screen (pro-rt-01…07),
  manual retopology that snaps to the surface (pro-rt-08n)
- **Simulations**: an XPBD cloth solver as a separate package, non-rotating
  rigid bodies, a simulation-frame cache, playing back the cache, exporting
  as morph targets, a simulation screen (pro-sim-01…06)
- **Offline rendering**: a scene snapshot through a dedicated CPU renderer
  with supersampling, a composite pass graph, a render screen
  (pro-rn-01…04)
- **Texture painting**: layers with blend modes, brush projection through
  baking, flattening layers on export, a painting screen (pro-pt-01…05),
  vertex-color painting (pro-pt-06n)
- **Engine changes needed for all of this**: partial texture rewrites
  (pro-eng-02), post rendering with an external HDR input (pro-eng-03), a
  shifted-perspective for tiled snapshots (pro-eng-04), pass profiling
  (pro-eng-05), LOD in the document format (pro-eng-06), fixed-width ribbons
  in the overlay (pro-eng-07)
- Project-format sections for all of this data (pro-doc-01), eight golden
  frames and an end-to-end scenario (pro-test-01), an "after phase 4"
  section explaining what gets pushed further out (pro-after-01)

## Game graphics — a parallel engine-work track (G1–G3)

Not part of the editor's phases: these items fix game rendering directly,
and the editor is the tool that made the gaps visible.

**✅ Done**
- A per-pass frame profiler as a first step, so further work is measured,
  not eyeballed (gfx-01n)
- FXAA, resolving the conflict between SSAO/reflections and anti-aliasing
  (gfx-04n)
- An additive pose layer over the base animation (gfx-10n)
- Ray hits against the animated pose, not the base shape (gfx-11n)
- Light channels (gfx-12n)
- Light and cameras from glTF (`KHR_lights_punctual`) (gfx-14n)
- Soft disc shadows instead of hard PCF (gfx-15n), alpha hashing for foliage
  and nets (gfx-16n), tone curves (gfx-17n) and the LUT sampled after them
  (gfx-18n)

**⬜ Not started**
- Measuring and possibly changing the default anisotropic filtering
  (gfx-02n, gfx-07n), distant shadows (gfx-03n, gfx-06n)
- Turning SSAO on by default now that it no longer fights anti-aliasing
  (gfx-08n) — held by the golden sets on the three backends this machine
  cannot re-record
- Physical light units (gfx-13n)
- Culling light sources by contribution instead of a hard cap of eight, with
  no "pop" as the camera moves (gfx-05n) — the selection and the fade are
  both built; what is left is the golden frame, which means turning the fade
  on for every backend
- Screen-space contact shadows (gfx-09n)

## Quality, infrastructure, and CI

**✅ Done**
- A green `main` build, structure-scanner rules for new packages (qa-01,
  qa-02), the "a flat Dart package resolves with no Flutter SDK" check
  (qa-03)
- CI reads the test list from flat packages (qa-04), a forbidden-word
  dictionary for the scanner's detector (qa-05)
- A CI benchmark artifact and a stress scene with a measurement table
  (qa-13)

**⬜ Not started**
- An enum/sealed policy as a scanner rule (qa-06)
- A formal half-edge invariant audit as a separate quality item, writer
  round-trips with fixtures and provenance (qa-07, qa-08), a glTF-validator
  check in CI (qa-09), an automatic check that a file opens in headless
  Godot (qa-19n)
- Golden scenes for the mesh overlay (qa-10), a conformance check for
  partial buffer rewrites (qa-11), an agent scenario and tool round-trip
  (qa-12)
- A draw-call-count guard (qa-14), app tests through software rendering
  (qa-15), documents kept in sync with the tree (qa-16), builds for every
  platform in CI (qa-17), format/command/history/readiness tests as a
  separate summary check (qa-18)

## Phase 0 measurements (the numbers decisions are built on)

**✅ Done** — the whole measurement block is closed, except two items:
a load-and-profiling rig (p0-01), a web measurement on Metal/WebGL2/WebGPU
(p0-02), the `EditMesh` spike (p0-04), choosing the persistent structure
(p0-05), comparing a full geometry reload against a partial one (p0-06), an
isolate versus chunks on the web (p0-07), three package skeletons under the
scanner (p0-09), a BVH prototype (p0-10), an end-to-end drag-and-drop
pipeline (p0-11), rolling results up into a document (p0-12), a save-under-
macOS-sandbox spike (p0-13n).

**⚠️ Partial**
- A measurement on an Android tablet/iPad (p0-03) — done on a Galaxy A55, an
  iPad measurement waits on buying the device (rel-19d)
- A web file-I/O spike (p0-08) — the base path works, opening `.gltf` with
  neighboring files (`.bin`, images) is a recorded gap, closed by a separate
  item (ui-36n)

## Publishing and product

**✅ Done**
- Package names locked in (rel-01), a skeleton for three new packages under
  the publishing system (rel-02), the scanner and publishing rules updated
  (rel-03), a build-with-no-Flutter-SDK check in CI (rel-04)
- A ROADMAP entry (rel-12), a phase-1 platform summary table (rel-17)

**⚠️ Partial**
- `SECURITY.md` with a list of formats in scope (rel-18) — started, not
  finished

**⬜ Not started**
- New packages' place in the publishing queue (rel-05), actually publishing
  to pub.dev for the first time (rel-06, deliberately deferred until phase 1
  is in users' hands)
- Editor-focused site sections (rel-08), a tutorial with a measured
  completion time (rel-09), a web demo on the site (rel-10)
- A macOS release build (rel-11), moving level templates onto model-editor
  documents (rel-13), reference material for the agent (rel-14)
- An in-app issue-report form (rel-15), a 5–10 person test cohort going
  through the tutorial (rel-16)
- Buying an iPad and setting up an Apple Developer account (rel-19d)

---

## What's next

**Big blocks left entirely unresolved:**
1. **Phase 3 — the character pipeline** (rigging, skinning, IK, retargeting,
   morph drivers, the animation timeline) — only the FK measurement is done.
   This is the only section of the plan where nothing functional has
   started at all.
2. **Phase 4 — professional modes** (sculpting, retopology, UV, cloth
   simulation, offline rendering, texture painting, LOD) — not started at
   all; the phase itself is flagged in the plan as "the least precise," and
   the L-sized estimates inside it could double once implemented.
3. **The "an agent that can see the model" track (mcp-*)** — today the agent
   works blind: MCP tools give readiness numbers, not a picture. Needs
   separate engine groundwork (`GraphicsDevice.present()` stops naming
   Flutter, the rendering core becomes a flat package) before a `render`
   tool can be added.
4. **The game-graphics track (gfx-*)** — engine fixes running alongside the
   editor (a frame profiler, light-source culling with no "pop," contact
   shadows, FXAA); not started, moves through its own G1–G3 phases rather
   than the editor's phases.
5. **The two remaining phase-2 items**: wrapping a boolean operation as a
   stack modifier (mesh-48) and phase-2 golden frames (mesh-49) — the core
   is done, the thin wrapper and the frames are not.
6. **Phase-2 materials and modifiers beyond the basic set**: a full material
   panel, a texture compositor (node graph), a material studio, a "Scene"
   mode with light, a modifier stack in the UI — the core (`mat-18`,
   `mat-19`, `mat-28`) is done, the whole user-facing layer and the texture
   graph are not started.
7. **Formats**: a dedicated FBX reader (two L-sized items), an offline
   texture encoder into compressed formats, USDZ, light/cameras in the
   format's own dictionary — none started.

**Open design questions (plan §8), not yet closed by an owner decision**
(the questions closed on 2026-09-09 are already reflected in the statuses
above and are not repeated here; the plan had 87 questions in total, 24
closed, 63 remain open across ten groups):
- **Timing** (A): the official phase-1 start date, the web-profile budget
  threshold
- **Data structures** (B): element-id stability (tombstones vs. dense
  renumbering), which attributes go per-vertex vs. per-corner
- **Packages** (C): whether a separate `bin/` mesh-checking tool is needed,
  versioning for new packages
- **Document/MCP** (D): the exact autosave location on disk, history depth
  in bytes, a Flutter-free PNG encoder (a homemade deflate or
  `package:archive`), whether to keep the original imported file whole
- **Formats** (E): whether the Khronos validator resolves under the current
  SDK, whether a second UV set is needed for lightmaps
- **Shell/platforms** (F): whether to show disabled future-phase modes in
  the switcher, the channel for opening files from the system file browser
- **Rendering/materials** (G): one modifier flag or two
  (`enabled`/`showInViewport`), exact texture-budget numbers per preset, the
  default bake resolution
- **Animation** (H): a hard skinning-influence limit or a phase-4 layout of
  eight, a standard facial-shape naming scheme or custom groups only
- **Phase 4** (I): the export format for a simulation result, the order of
  the three render-contract changes across phases
- **Quality/publishing** (J): who runs the nightly build of the reference
  Impeller/WebGL/WebGPU sets for new scenes, whether an automatic
  number-recompute tool is needed for the documents

Every one of these questions has a recommendation in the plan itself (§8) —
these are not gaps, but decisions left to the product owner at the point
each phase actually starts.
