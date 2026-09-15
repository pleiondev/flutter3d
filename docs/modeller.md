# The modeller — what it actually does

A factual inventory of `apps/flutter3d_modeler` as the code stands today,
not a plan. Every claim below is checked against source (file:line), not
against `doc/model-editor.md` or `doc/model-editor-plan.md` — those are
earlier planning documents, and several of their "missing" rows (glTF/OBJ/
STL export, LOD simplification that keeps UV and skin weights) are now
wrong: the feature landed since they were written. Where this document
disagrees with them, this document is the current truth; treat the older
two as historical record of how the plan evolved, not as a functional
reference.

Two front doors reach the same document: the desktop/web GUI
(`apps/flutter3d_modeler`), and an MCP tool surface
(`packages/flutter3d_model_mcp`) any client — human-driven UI, a headless
script, or an agent — can drive over `--mcp-port`. Everything the GUI does
to `ModelHistory`, an MCP tool call can do too, through the identical
`ModelCommand` machinery; the reverse is not quite true (seven `ui.*`
tools exist only when a live GUI window is the one answering MCP calls).

---

## 1. The document

`ModelProject` (`packages/flutter3d_model_core/lib/src/project.dart:503`,
`implements ModelProjectView`) is the whole authored state:

- `profile: ProjectProfile` — export budgets (§18).
- `objects: List<ModelObject>` — order is add-order, outliner order, and
  export order.
- `materials: List<ProjectMaterial>`, `images: List<EncodedImage>` — a
  material references images by index into this table, not by embedding
  bytes per-material.
- `skeletons: List<ProjectSkeleton>`, `clips: List<ProjectClip>`.
- `lighting: SceneLighting` — **not written to the file format yet**
  (project.dart:539): a project saved and reopened comes back with the
  default (no lights, no environment). Live editing works; persistence
  does not.
- `nextId: int` — only ever grows; an id is never reused after deletion.

`ModelObject` (project.dart:381): `id` (stable for the object's lifetime),
`name`, `geometry` (sealed, four variants below), `transform` (local to
`parent`), `parent: int?`, `version: int` (bumped on every change, so the
viewport can skip re-uploading an object that did not move), `materialSlots:
List<int>` (not a single index — a list, into `project.materials`),
`modifiers: List<ModifierSlot>`, `skeletonIndex: int?`, `shapeSet:
ShapeSet` (morph targets plus their current preview weights),
`shapeDrivers: List<ShapeDriver>` (morphs driven by a joint's own
rotation, not a slider — see §11), `lods: List<LodSpec>` (most detailed
first), `simulationCache: SimulationCache?` (also not persisted to the
file format, same honest gap as `lighting`).

**Geometry — four variants** (`Geometry`, sealed, project.dart:283):

- `ParametricGeometry(shape)` — still a primitive/lathe/etc, editable by
  changing its own parameters (§6), not by pushing vertices around.
- `EditedGeometry(mesh: EditMesh)` — real, editable topology (§7), reached
  either by baking a parametric shape or by building one from scratch.
- `ImportedGeometry(data: MeshData)` — raw GPU-ready buffers straight off
  an importer, no topology.
- `SocketGeometry()` — an empty marker object (an attachment point), zero
  triangles/vertices.

---

## 2. History, undo, and the journal

`ModelHistory` (`packages/flutter3d_model_core/lib/src/history.dart`):

- `String? run(ModelCommand command, {StepAuthor author = StepAuthor.person})`
  (:204) — `null` on success, a refusal sentence otherwise.
- `String? amend(ModelCommand replacement)` (:388) — re-runs the
  replacement against the document as it was **before** the step on top,
  rather than pushing a second step. This is what an `OperationCard`
  slider drag does, and what the `amend` MCP tool does over the wire.
- `bool undo({StepAuthor? onlyIfAuthoredBy})` (:438) — with
  `onlyIfAuthoredBy` set and not matching `topStepAuthor`, silently
  returns `false` and changes nothing (:427-440). This one check is the
  entire mechanism behind "an agent does not undo a person's own step" —
  the Agent Session panel's "Undo agent steps" button is gated on exactly
  this.
- `beginTransaction()` / `endTransaction()` (:297, :319) — one undo step
  per whole drag, not per pointer-move event.
- `enum StepAuthor { person, agent }` (:48). Every command an MCP tool
  call reaches `ModelSession` with runs as `StepAuthor.agent`
  unconditionally; a live UI edit that goes through `ModelerCubit.run`
  (no author named) defaults to `StepAuthor.person`.
- `journal` (the undo stack itself, :508) is not the same thing as the
  recovery journal below — same word, two different lists.

`CommandJournal` (`command_journal.dart`) is a separate, append-only
recovery log: JSON Lines, one command per line (a crash mid-write loses at
most the last line, not the whole file), written only after `run`
succeeds. Because it replays commands cold, any command whose behaviour
depends on live UI state rather than its own JSON arguments would replay
wrong — which is why selection itself now runs as a real command
(`SelectElements`, via `ModelSession.select`) instead of assigning
`history.selection` directly.

**Every `ModelCommand` subclass** (~95, `grep -rn "extends ModelCommand"`),
grouped by file:

| File | Commands |
|---|---|
| `command.dart` | `ReplaceDocument`, `Rename`, `SetTransform`, `MoveBy`, `DeleteObjects`, `DuplicateObjects` |
| `object_commands.dart` | `AddPrimitive`, `AddLathe`, `AddSocket`, `SetParametric`, `BakeToMesh`, `SetParent`, `RotateBy`, `ScaleBy`, `SetOrigin`, `ApplyTransform` |
| `mesh_commands.dart` | `Extrude`, `LoopCut`, `BevelEdges`, `DeleteElements`, `TransformElements`, `MergeByDistance`, `DissolveEdges`, `MarkSeam`, `Triangulate`, `RecalculateNormals`, `Separate`, `FillHoles` |
| `selection_commands.dart` | `SelectAll`, `SelectNone`, `InvertSelection`, `GrowSelection`, `ShrinkSelection`, `SelectLinked`, `SelectEdgeLoop`, `SelectEdgeRing`, `SelectByMaterial`, `SelectElements` |
| `material_commands.dart` | `AddMaterial`, `RemoveMaterial`, `DuplicateMaterial`, `SetMaterialField`, `SetMaterialGraph`, `BakeTextureGraph`, `SetTexture`, `AddImage`, `AssignMaterial`, `LinkMaterialFile`, `EmbedMaterial` |
| `texture_graph_commands.dart` | `AddNode`, `Link`, `Unlink`, `SetNodeField`, `MoveNode`, `RemoveNode` |
| `modifier_commands.dart` | `AddModifier`, `SetModifierField`, `ToggleModifier`, `ReorderModifier`, `RemoveModifier`, `ApplyModifier` |
| `joint_commands.dart` | `AddSkeleton`, `BindSkin`, `AddJoint`, `RemoveJoint`, `RenameJoint`, `ReparentJoint`, `SetRestPose`, `MirrorJoints` |
| `keyframe_commands.dart` | `AddClip`, `PoseJoint`, `SetKey`, `MoveKeys`, `DeleteKeys`, `SetInterpolation`, `SetTangent` |
| `shape_commands.dart` | `SetShapeWeight`, `AddShapeFromMesh`, `RenameShape`, `DeleteShape`, `KeyShape`, `AddShapeDriver`, `RemoveShapeDriver`, `SetShapeDriverField` |
| `lighting_commands.dart` | `AddLight`, `RemoveLight`, `SetLightField`, `SetLightTransform`, `SetEnvironment`, `SetSceneLightingField` |
| `lod_commands.dart` | `AddLod`, `SetLodRatio`, `RegenerateLods` |
| `root_motion_commands.dart` | `ExtractRootMotion`, `BakeRootMotionIntoClip` |
| `simulation_commands.dart` | `ApplySimulationCache`, `BakeSimulationToShapes` |
| `profile_commands.dart` | `SetProfileLimits` |
| `uv_commands.dart` | `UnwrapCommand` |
| `set_rig.dart` | `SetRig` |
| `job_commands.dart` | `ApplyJobResult` |
| `rig_job_commands.dart` | `ApplyClipResult` |
| `paint_weights.dart` | `PaintWeights` |

---

## 3. MCP transport

`ModelSession` (`packages/flutter3d_model_mcp/lib/src/model_session.dart:36`)
— one process, one open project ("There is no `open` tool and no second
project"; a host wanting two projects starts two processes). `select(...)`
(:176), `run(command)` (:201) and `amend(to)` (:226) all run as
`StepAuthor.agent` unconditionally.

`ModelHttpServer.start({session, port: 0, token, extraTools, onToolCall})`
(`model_http_server.dart:53`) binds `127.0.0.1:$port`, loopback-only,
token-gated, one JSON-RPC message per request. On launch it writes
`mcp-session.json` (port + token) into the platform's application-support
directory — the file any MCP client reads to find and authenticate to
this exact running window. `extraTools` is the only door through which the
GUI adds the seven `ui.*` tools (§5); the headless entry point
(`bin/model_mcp.dart`) does not pass any, so a headless session's
`tools/list` never shows them. `onToolCall` feeds the Agent Session
panel's live tool-call feed (§5).

---

## 4. UI modes and layout

`enum ModelerMode` (`apps/flutter3d_modeler/lib/src/ui/tools.dart:62`) — 8
values, each carrying `(label, icon, phase, {required ready})`:

| Mode | Phase | `ready` |
|---|---|---|
| `object` | 1 | true |
| `mesh` | 1 | true |
| `material` | 2 | true |
| `uv` | 4 | false |
| `sculpt` | 4 | false |
| `animation` | 3 | true |
| `render` | 4 | false |
| `scene` | 2 | true |

`kPhoneModes` (:101) exposes only four on a phone-width window: `object`,
`mesh`, `material`, `scene` — `animation` does not fit the phone's
`NavigationBar` even though it is `ready`.

Submodes: `enum MeshSubmode { vertex, edge, face }` (:115, shortcuts 1/2/3)
and `enum AnimationSubmode { pose, weights, retarget, morphs }` (:141,
shortcuts 1-4). A separate, deliberately distinct type,
`ElementLevel { vertex, edge, face }`
(`packages/flutter3d_mesh/lib/src/selection.dart:34`), is the *document's*
notion of selection level; `MeshSubmode` is the *interface's*.

**Tool rail, per mode** (`toolsFor`, `tools.dart`):

- Object: `object.select`, `.move`, `.rotate`, `.scale`, `.add`,
  `.duplicate`, `.bake`, `.lathe`, `.origin`, `.apply`, `.delete`.
- Mesh: `mesh.select`, `.move`, `.rotate`, `.scale`, `.extrude`,
  `.loopCut`, `.bevel`, `.triangulate`, `.separate`, `.dissolve`,
  `.merge`, `.normals`, `.flip`, `.delete`.
- Animation/pose: `pose.select`, `.key`, `.deleteKey`, `.autoRig`.
- Animation/weights: `weights.paint`, `.assign`, `.mirror`, `.normalize`.
- Animation/retarget: `retarget.import`, `.autoMap`, `.apply`.
- Animation/morphs: `morphs.add`, `.key`, `.delete`.

`kDragTools` (:34) need a pointer drag (object/mesh move/rotate/scale);
`kStrokeTools` (:54) are continuous-stroke (`weights.paint`,
`weights.assign` — mirror/normalize fire once, not by stroke).

**Properties panel sections, per mode**
(`sectionsFor`, `apps/flutter3d_modeler/lib/src/ui/properties_sections.dart:79`):

- Every mode: `display`, `view`, `budget`.
- `object`: `objects`, `transform`, `modifiers`, `materials`.
- `mesh`: `lastOperation`, `selection`, `mesh`.
- `animation`, by submode: `pose→animation`, `weights→weightPaint`,
  `retarget→retarget`, `morphs→morphs`.
- `scene`: all four of `sceneSources`, `sceneShadows`, `sceneEnvironment`,
  `scenePost` at once.
- `material`, `uv`, `sculpt`, `render`: **no sections at all.**

This last row is a deliberate, named interim decision, not an oversight:
the mode switcher's own `Material` button is marked `ready: true` and
switches modes cleanly, but has no panel of its own yet — the comment at
`properties_sections.dart:56-61` says outright that a full `Material`
workspace is `ModelerMode.material`'s own phase-2 row, and until it lands,
material editing lives under Object mode instead (`PropertiesSection
.materials` is attached to `ModelerMode.object`'s own case). A person or
an agent switching to `Material` mode expecting to see material controls
will see nothing; switching to `Object` mode is where they actually are.

**Layout / breakpoints**
(`apps/flutter3d_modeler/lib/src/ui/layout_class.dart:41`):
width `<600` → phone, `<1200` → tablet, otherwise desktop. All three shells
are built and wired (`shell_for_width.dart:81-113`):
`desktop→ModelerShell`, `tablet→ModelerTabletShell`,
`phone→ModelerPhoneShell`. On tablet, the tool rail collapses to a 48px
icon column and the properties panel becomes a 200px bottom sheet with a
drag handle — access to properties is not lost, only reshaped. On phone,
mode switching moves to a bottom `NavigationBar` and every tool in
`toolsFor` reaches a single FAB that opens the same table as a sheet.

**Agent Session panel**
(`apps/flutter3d_modeler/lib/src/ui/agent_session_panel.dart`) — appended
after the ordinary properties panel whenever `--mcp-port` is open, never
replacing it. Shows: a live tool-call feed (every MCP call that answered,
fed by `ModelHttpServer`'s `onToolCall`); a history list with You/Agent
badges read straight from `ModelHistory.steps`; an "Undo agent steps"
button gated on `ModelHistory.topStepAuthor == StepAuthor.agent`. Its
**contact sheet** is not a live multi-camera view — nothing in the
application draws more than one viewport at a time outside `render`/
`renderSheet` themselves. It shows the actual pictures those two tools
drew this session, most recent first, captioned with whatever view/mode
was asked for — "real answers an agent received," per the panel's own
library comment, not a camera rig standing by for a call that may never
come.

**The seven `ui.*` tools** (`apps/flutter3d_modeler/lib/src/mcp_ui_tools.dart`,
GUI-only, absent from a headless session):

1. `ui.setMode(mode)` — clicks the mode switcher; refuses an unknown name.
2. `ui.setSubmode(submode)` — the current mode's own second switcher
   (vertex/edge/face for mesh, etc); refuses if the current mode has none.
3. `ui.setTool(id?)` — lights a rail tool; no `id` clears the active tool.
4. `ui.standardView(view)` — camera to one of the six standard views
   (front/back/left/right/top/bottom).
5. `ui.frameSubject()` — frames the current subject.
6. `ui.openDialog(dialog)` — opens one of export/lathe/autorig/preview
   without waiting for it to close, meant for screenshot scripts.
7. `ui.say(text)` — writes a sentence to the status line, marked to
   survive the line's ordinary auto-clear — for a screenshot script to
   caption a step.

---

## 5. Object-level editing

- `addPrimitive {kind, size?, segments?, at?}` — `kind` ∈ `box`, `plane`,
  `sphere`, `cylinder`, `torus` (`AddPrimitive.primitiveKinds`,
  `object_commands.dart:67-73`). Stays parametric until baked.
- `addLathe {profile: [[r,h],...], segments?, closedProfile?, label?, at?}`
  — revolves a (radius, height) profile around an axis; `closedProfile`
  joins the last point back to the first (a torus shape).
- `addSocket {label?, at?}` — a named attachment point with no geometry;
  exports as an empty group/node.
- `setParametric {id, to: {shape, ...fields}}` — edits a still-parametric
  shape's own parameters; refused on a mesh or an imported object.
- `bakeToMesh {id}` — turns a parametric shape into an editable mesh.
  There is no command that reverses this directly; `undo` restores the
  whole parametric shape instead.
- `deleteObjects` / `duplicateObjects` — act on the current selection, no
  id argument; delete also takes everything parented under the selection.
- `rename {id, to}`, `setTransform {id, to: matrix16}`,
  `moveBy {by}` (acts on selection), `rotateBy {axis, radians, pivot?,
  space?}` (`pivot`: median default | individual; `space`: global default
  | local), `scaleBy {by (>0), pivot?}`.
- `setParent {id, to?}` — no `to` detaches to top level; the child keeps
  its **local** transform, not its world position.
- `setOrigin {id, to?}` — `to` ∈ `boundsCentre` (default) |
  `boundsBottom` | `worldOrigin`; geometry and node shift oppositely so
  the visible position does not move.
- `applyTransform {id}` — bakes the node's transform into the geometry,
  leaving identity; needed before exporting to engines that expect a
  model to start at the origin.

---

## 6. Mesh editing

`EditMesh` (`packages/flutter3d_mesh/lib/src/edit_mesh.dart:49`) is the
half-edge topology structure — distinct from `MeshData`, the GPU-ready
format with duplicated corners per normal. Six flat `Int32List`/
`Float32List` arrays through `JournalledInts`/`JournalledFloats`, so every
edit is journalled and reversible: each half-edge knows its origin
vertex, `next` (around the face), `twin` (across the edge), and face;
each vertex knows one outgoing half-edge; each face knows one half-edge on
its own loop. Deletion is a tombstone, not a hole in the array — an
element is marked dead and skipped; `compact()` collapses the gaps and
returns an `IdRemap` (old id → new id, or `EditMesh.none` if deleted).
N-gons (faces of any valency) are supported natively.

Mesh-mode tools:

- `extrude {distance}` — pulls selected faces along their normal.
- `loopCut {cuts?, factor?}` — cuts N loops through the selected faces
  (`factor` 0–1, default 0.5, centred).
- `bevelEdges {width}` — chamfers selected edges/vertices; requires a
  closed region (every face touching a bevelled edge must have all its
  own edges bevelled too).
- `deleteElements` — removes the current-level selection.
- `transformElements {by: matrix16, what?, pivot?, space?}` — the
  element-level analogue of `setTransform`; `pivot: individual` is
  refused here.
- `mergeByDistance {distance?}` — welds vertices closer than `distance`.
- `dissolveEdges` — removes selected edges, merging the faces either
  side.
- `triangulate` — cuts every face with more than three corners into
  triangles.
- `recalculateNormals {flip?}` — rebuilds vertex normals from faces.
- `markSeam {on?}` — marks/clears selected edges as a UV seam.
- `unwrap {margin?, autoPack?}` — lays out UV for the selected faces (or
  the whole mesh, if nothing is selected), cutting at seams; `autoPack`
  (default true) packs the resulting islands into the shared `[0,1]`
  square.
- `separate` — moves the selected faces into a new object in place.
- `fillHoles` — closes every open boundary loop with one new face each;
  refused if there are none. This is the direct fix for the "won't load:
  an open edge" export warning.
- Selection: `selectAll` / `selectNone` / `invertSelection` (current
  level); `growSelection` / `shrinkSelection` (by connectivity);
  `selectLinked`; `selectEdgeLoop` / `selectEdgeRing {edge}`;
  `selectByMaterial {slot}` (mesh mode only).

---

## 7. Modifiers

A stack of modifiers lives on each object (`addModifier {id, modifier:
{kind, ...}}`). Five kinds:

- **array** — `count` (total instances including the original), `offset`
  (3 numbers, added per copy), optional `mergeDistance` (welds seams).
- **mirror** — `normal` (3 numbers, plane through the object's origin),
  optional `mergeDistance`. `bisect` is refused — not implemented.
  `flipUv` is accepted but currently stored with no effect.
- **smooth** — `iterations` (≥1), optional `lambda` (0-1, per-pass move
  toward neighbour average), optional `preserveVolume` (without it, many
  iterations visibly shrink the mesh).
- **subdivision** — `levels` (≥1, real baked Catmull-Clark passes),
  optional `viewLevels` (defaults to `levels`; nothing currently reads
  it — reserved for a future live-preview viewport).
- **boolean** — `operation` (union/subtract/intersect), `operandId`
  (second object's id), `operandTransform` (matrix16, operand-local into
  this object's local space). The operand is only named when the
  modifier is added; combining happens when the stack is evaluated.

Stack tools: `setModifierField {id, index, field, value}`,
`toggleModifier {id, index}`, `reorderModifier {id, from, to}`,
`removeModifier {id, index}`, `applyModifier {id, index}` (bakes that
modifier and everything below it into the mesh — even if currently
disabled, matching export behaviour — leaving modifiers above it running
against the new base mesh).

---

## 8. Materials and textures

`SurfaceMaterial` (`packages/flutter3d_formats/lib/src/surface_material.dart:141`):
`name`, `baseColor` (**Vector4, RGBA**, default opaque white),
`metallic`/`roughness` (double, defaults 0.0/0.5), five texture bindings
(below), `normalScale`/`occlusionStrength` (default 1.0), `emissive`
(Vector3, RGB — not RGBA), `emissiveStrength` (default 1.0), `alphaMode`
(`opaque`/`mask`/`blend`), `alphaCutoff` (default 0.5), `doubleSided`,
`unlit` (both default false), `lightingModel` (nullable — null lets the
renderer pick unlit/pbr from the `unlit` flag), `extras` (raw glTF
passthrough).

`setMaterialField`'s field vocabulary (`model_tools.dart:113-124`): `name`,
`baseColor`, `metallic`, `roughness`, `normalScale`, `occlusionStrength`,
`emissive`, `emissiveStrength`, `alphaMode`, `alphaCutoff`, `doubleSided`,
`unlit`. Texture slots do **not** go through `setMaterialField` — only
through `setTexture`.

**Five texture slots** (`setTexture {materialIndex, slot, imageIndex?,
wrapS?, wrapT?}`): `albedo`, `normal`, `metallicRoughness`, `occlusion`,
`emissive`. `wrapS`/`wrapT` ∈ `repeat` (default) | `clampToEdge` |
`mirroredRepeat`. Omitting `imageIndex` clears the slot.

**Six built-in lighting models**
(`packages/flutter3d_formats/lib/src/lighting_model.dart:108-115`,
`builtIn`): `unlit`, `lambert`, `blinnPhong`, `pbr` ("PBR (GGX)"), `toon`,
`normals`. A seventh, `xray`, exists but is deliberately excluded from
`builtIn` — it is a render-pass stage, not a material a person picks.
Each model is a `const LightingModel` value carrying capability flags
(`usesMetallic`, `usesEnvironment`, `usesMaterialMaps`, …), used to
validate a shader bundle, not only to pick a shader — the list is open to
extension by whatever application assembles its own bundle.

Material tools: `addMaterial {materialName?}`, `removeMaterial {index}`
(objects holding that index lose their material assignment; later indices
shift down), `duplicateMaterial {index}`, `setMaterialField`, `setTexture`,
`addImage {bytes(base64), imageName?, mimeType?}` (content-interned —
identical bytes twice reuse one row, no duplicate upload),
`assignMaterial {id, to?}` (no `to` unpaints), `setMaterialGraph
{materialIndex, graph?}` (no `graph` clears it).

**Texture graph — 11 node kinds**
(`packages/flutter3d_model_core/lib/src/texture_graph.dart`, all `sealed
class TextureNode`):

| Node | Fields |
|---|---|
| `image` | `imageId` |
| `color` | `value: Vector4` (no inputs) |
| `blend` | `base?`, `overlay?`, `mode` (normal/multiply/add/screen), `factor` |
| `channels` | `source?`, `channel` (r/g/b/a) — colour→scalar |
| `levels` | `source?`, `blackPoint`, `whitePoint`, `gamma` |
| `invert` | `source?` — `1 - input`, scalar→scalar |
| `uvTransform` | `source?`, `offset`, `scale`, `rotation` (radians) |
| `checker` | `colorA`, `colorB`, `scale` (1-64), no inputs |
| `noise` | `seed`, `scale` — deterministic by seed, not `Random` |
| `normalFromHeight` | `height?`, `strength` (0-8) — height mask → tangent-space normal |
| `output` | `result?`, `slot?` — `slot` names one of the five texture slots; an `output` with no `slot` is preview-only |

`bakeTextureGraph {materialIndex, size=1024}` bakes synchronously into
pixels, one undo step for the whole graph; refused if the graph is
missing/invalid, or if no output node named a slot.

`linkMaterialFile {index, path, bytes?}` / `embedMaterial {index}` — a
material can point at an external `.fmat` file. With `bytes`, the
material adopts every scalar/colour/alpha/doubleSided/unlit field from it
(texture slots must still be imported separately); without `bytes`, only
the path is remembered, for a file that does not exist yet. `embedMaterial`
drops the file link without changing the look.

---

## 9. LOD

`addLod {id, ratio (0,1], maxScreenFraction}`, `setLodRatio {id, lodIndex,
ratio}`, `regenerateLods {id}` (forces every cached LOD mesh to
recompute — for changing the simplification algorithm itself, not for
ordinary editing, which already bumps the version).

Simplification is quadric-error-metric edge collapse (Garland–Heckbert),
`packages/flutter3d_mesh/lib/src/qem_simplify.dart`: `simplifyMesh`
(positions only) and `simplifyMeshWithAttributes` (keeps UV, normals,
skin weights, with a boundary/seam penalty — a Hoppe-style extension).
`packages/flutter3d_model_core/lib/src/lod_cache.dart:65` calls
`simplifyMeshWithAttributes` — **attribute-preserving simplification is
implemented and in use**, contradicting `doc/model-editor.md`'s older
"missing" row for it.

---

## 10. Rigging and skinning

`RigTemplate.humanoid` (`packages/flutter3d_model_core/lib/src/rig_template.dart:405-436`):
`hips` (root) → 1-3 spine segments (`spineCount`) → `chest` → `neck` →
`head`, plus mirrored `leftShoulder/rightShoulder →
leftElbow/rightElbow → leftWrist/rightWrist` and `leftHip/rightHip →
leftKnee/rightKnee → leftAnkle/rightAnkle`. Optional: `fingers` (five
three-phalanx fingers per hand), `toes` (one joint per foot), `faceBones`
(jaw + two eyes). The canonical 17-bone base case (`spineCount=1`, no
options) — `packages/flutter3d_rig/lib/src/bone_map.dart:14-30` — is:
`hips, spine, chest, neck, head, leftShoulder, rightShoulder, leftElbow,
rightElbow, leftWrist, rightWrist, leftHip, rightHip, leftKnee, rightKnee,
leftAnkle, rightAnkle`.

`RigTemplate.quadruped` (:438-464) — 15 joints: `pelvis, spine1, chest,
neck, head, tailBase, tailTip` plus mirrored `leftFrontShoulder/
rightFrontShoulder → leftFrontPaw/rightFrontPaw` and
`leftBackHip/rightBackHip → leftBackPaw/rightBackPaw`. `fingers`/`toes`/
`faceBones`/`ikChains` are humanoid-only options — a quadruped has no
elbow/knee joint to hang them on.

`autoRig {template ('humanoid'|'quadruped'), markers{name→[x,y,z]},
skinObjectId?, skeletonName?, mirrorAxis?, bounds?, spineCount?, fingers?,
toes?, faceBones?, ikChains?, controllers?}` — builds a skeleton from
world-space marker positions, one per joint the chosen template requires
(a missing/invalid marker is named in the refusal). Only the left half
and the centre line need markers; each right joint mirrors its left
counterpart. Refused if the chosen option combination would exceed the
skinning shader's 64-joint limit.

`looseAutoMap` (`bone_map.dart:94-391`) reads a source skeleton's names in
three passes:

1. **`autoMap`** — exact-name intersection, 1:1.
2. **`looseAutoMap`, pass one** — strips a rig-family prefix
   (`mixamorig:`, `bip01_`/`bip01 `, case-insensitive), finds a side
   (`left`/`right` at the start, or an `l_`/`r_` token), then matches
   words against two synonym tables: central (`hips/hip/pelvis/root
   →hips`, `spine/spine1→spine`, `chest/spine2/upperchest→chest`,
   `neck`, `head`) and limb, once a side is known
   (`shoulder/clavicle/arm/upperarm→Shoulder`, `elbow/forearm/lowerarm
   →Elbow`, `wrist/hand→Wrist`, `hip/thigh/upleg→Hip`,
   `knee/leg/calf/shin→Knee`, `ankle/foot→Ankle`). Known imprecision:
   `shoulder` and `arm` both resolve to `Shoulder` — a source naming both
   (Mixamo's `LeftShoulder` + `LeftArm`) has the later one win.
3. **`looseAutoMap`, pass two** — for a generic name carrying a numeric
   chain index as its own token (`torso_joint_1`, `arm_joint_L_2`, no
   word any synonym table recognises), maps **by position in the chain**
   rather than by word: `torso`→[hips,spine,chest] by index 1/2/3,
   `neck`→[neck,head] by index 1/2, `arm`→[Shoulder,Elbow,Wrist],
   `leg`→[Hip,Knee,Ankle]. The index must be its own token — a
   Blender-style `Spine1` with no separator is not read this way. A
   source chain shorter than the template does not guess past its own
   end.

Joint tools: `addSkeleton {skeletonName?}`, `bindSkin {objectId,
skeletonIndex}`, `addJoint {skeletonIndex, objectId, inverseBindMatrix?}`,
`removeJoint` (weights fall to the parent joint, or renormalize without
one), `renameJoint`, `reparentJoint` (refused on a cycle), `setRestPose
{skeletonIndex, jointIndex, worldTransform}` (recomputes local transform
and inverse bind matrix so the mesh does not jump), `mirrorJoints
{skeletonIndex, axis, jointMirror}`. `setRig {jointObjects[], skeleton{...},
skinObjectId?, weights?{baseVersion, data}, label}` lands a whole rig
result — joints, skeleton, optional binding and weights — as one undo
step; weights are base64 Float32, 8 numbers per vertex slot (4 joint
indices + 4 weights). `validateRig` is read-only: over-budget joint
counts, weights that do not sum to one, a weight naming a joint that does
not exist, a joint with no weight at all.

**Weight painting**: `paintWeights {objectId, skeletonIndex, joint,
samples[{center,radius}], strength, mode ('paint'|'assign'), mirror?,
normalize? (default true), maxInfluences?}`. `paint` blends with existing
influence; `assign` replaces a vertex's whole influence list with one
joint. `normalize` trims each touched vertex to `maxInfluences` (default:
the project profile's own limit) and renormalizes, after mirroring too.

**Budget**: `packages/flutter3d_model_core/lib/src/profile_commands.dart`
— `maxInfluences ∈ 1..4`, `maxJoints ≤ 64` (the skinning shader's own
per-draw joint array size) are hard ceilings, refused with an explanation
rather than silently clamped.

---

## 11. Animation, retargeting, morphs

`AnimationPath` (`packages/flutter3d_formats/lib/src/animation/animation_track.dart:43-50`):
`translation` (3), `rotation` (4, quaternion), `scale` (3), `weights` (0,
morph weights). Interpolation: `linear`/`step`/`cubicSpline`; tangents
persist even when cubic is not the active mode.

Keyframe tools: `setKey {clipIndex, trackIndex, time, values, inTangent?,
outTangent?}`, `moveKeys {..., indices, deltaTime}`, `deleteKeys` (refused
if it would leave a track with zero keys), `setInterpolation`,
`setTangent`, `poseJoint {joint, path, clipIndex, frame}` (keys the
object's own current live transform; a second call on the same frame
replaces the key rather than adding another), `addClip {clipName?}`.

**Root motion**: `extractRootMotion {clipIndex, rootJoint}` flattens the
root's translation track to its first key's value (refused if already
extracted, having first saved the real values on the clip);
`bakeRootMotionIntoClip` is the exact inverse (refused if nothing was
extracted, or the key count changed since).

**Retargeting**: `retargetClip {sourceClipIndex, sourceSkeletonIndex,
targetSkeletonIndex, boneMap?, lockFeet? (default true), groundY? (default
0), footTolerance? (default 1e-3), clipName?}` — rest-relative rotation,
translation scaled by height, default two-bone-IK foot lock; lands as a
new clip. No `boneMap` falls back to auto-mapping by matching names.
`RetargetRootMotion` (`apps/flutter3d_modeler/lib/src/ui/retarget_panel.dart:22-24`):
`inAnimation` | `inCode`.

**IK**: the only kind implemented anywhere in the tool surface is a
two-bone chain (root/mid/effector/target/pole) — in `RigBuildOptions
.constraints`, in `bakeIk`, and in `setRig`. `bakeIk {clipIndex,
rootJointId, midJointId, effectorJointId, target, pole, fps? (default
30)}` solves the chain at every `1/fps` second of the clip and writes
baked rotation keys for the root and mid joints — export always plays the
baked clip, never a live IK constraint.

**Shape-driven morphs**: `bakeDrivers {clipIndex, shapeTargetObjectId,
drivers?}` bakes one or more shape-key drivers into a weights track on the
clip (additively, if several drivers touch the same shape); with no
`drivers`, bakes whatever drivers the object has already accumulated via
`addShapeDriver {id, driver{shapeIndex, jointId, axis, from, to}}` — a
shape key driven by a joint's own rotation around one axis, rather than a
manual slider.

**Morph/shape-key tools**: `setShapeWeight {id, shapeIndex, weight}` (live
preview weight, not a keyframe); `addShapeFromMesh` (alias `addShape`)
`{id, shapeName}` — captures a new shape key from the mesh's current
vertex positions (sculpt first, then save), starting at weight 0;
`renameShape`, `deleteShape` (also removes the matching component from
any animation weights track); `keyShape {id, clipIndex, time}` — records
the shape's current weights as a keyframe, creating a weights track if
none exists; `removeShapeDriver`, `setShapeDriverField`.

`applyClipResult` and `applyJobResult` land a clip or a mesh that was
computed outside the synchronous tool call (`retargetClip`/`bakeIk`/
`bakeDrivers` compute and apply in one call themselves; these two exist
for a result an agent computed separately, or that came back from a
background job — `applyJobResult` is refused if `baseVersion` is stale).

---

## 12. Scene and lighting

`SceneLighting` (`packages/flutter3d_model_core/lib/src/scene_lighting.dart:178-223`):
`lights: List<ProjectLight>`, `environment` (default `none`),
`ambientIntensity` (default 0.3), `shadows` (bool, default false),
`exposure` (default 1.6), `post: ScenePostSettings` (default).

`ProjectLight` (:53-113): `type`, `color` (Vector3, linear RGB, default
white), `intensity` (default 1.0), `range` (default 0 = unbounded),
`castsShadow` (default false), `innerConeAngle`/`outerConeAngle` (spot
only, default 0 / π/4), `transform` (positions the light the same way an
object's transform positions it).

`ProjectLightType` and `SceneEnvironmentPreset` are deliberately **value
classes, not enums** (:28-45, :129-154) — same reasoning as
`LightingModel` — so the list stays open. Current values: light types
`directional`, `point`, `spot`; environment presets `none`, `studio`,
`daylight`, `sunset` (a fixed built-in set, not an importable panorama).

`ScenePostSettings` (:166-173) currently has exactly one field:
`bloomEnabled` (default true) — narrow on purpose, "not mirroring the
whole engine `RenderSettings`/`BloomSettings` until a specific plan row
asks for more."

Tools: `addLight {type?}`, `removeLight {index}`, `setLightField {index,
field, value}` (fields: `type`, `color`, `intensity`, `range`,
`castsShadow`, `innerConeAngle`/`outerConeAngle` — spot only),
`setEnvironment {preset}`, `setSceneLightingField {field, value}`. The
tool's own advertised schema enumerates only `ambientIntensity`,
`shadows`, `exposure` (`model_tools.dart:2087-2089`) — but the command it
dispatches to, `_sceneLightingFieldSet`
(`packages/flutter3d_model_core/lib/src/lighting_commands.dart:278-296`),
also has a working `'bloomEnabled'` (bool) case, and nothing in this
codebase validates a tool call's arguments against its own advertised
schema before running it. In practice `setSceneLightingField {field:
'bloomEnabled', value: true}` sets it — it is real, working, undocumented
surface, not a missing one; a client relying only on `tools/list` would
never discover it.

**Eight lights maximum** — `apps/flutter3d_modeler/lib/src/scene_mode.dart:64`,
`LightBuffer.maxLights = 8`; a ninth light in one draw call turns the
scene status orange (`lightOverflowOf`,
`packages/flutter3d_model_core/lib/src/lighting_sync.dart:134`).

---

## 13. Simulation

`applySimulationCache {objectId, baseVersion, ...}` writes a baked
`SimulationCache` (vertex count + a list of base64 Float32 frames) onto an
object; refused if `baseVersion` does not match the object's current
version. **The bake itself is not a single MCP tool call** —
`BakeClothJobRequest` (a real, existing class — cloth simulation is
implemented in the engine) has no synchronous, one-shot form a tool call
could wait on, so it runs only as a background job outside the tool
table. `bakeSimulationToShapes {objectId, maxKeys? (default 8)}` turns a
simulation cache into up to `maxKeys` shape keys, one per baked frame,
named by frame number; refused with no cache, no mesh to key, or a vertex
count mismatch. `setProfileLimits {maxJoints? (1-64), maxInfluences?
(1-4)}` — an omitted field is left unchanged.

---

## 14. Document-wide tools

- `list` — every object (id/name/kind) + the material table + current
  selection. Ids are stable but new (duplicated/imported) ones are only
  known after calling this.
- `listMaterials` — the full material table, row by row, including which
  texture slots are painted, whether a `.fmat` link exists, and whether a
  texture graph is unbaked.
- `check` — what would go wrong at export: budgets, n-gons, manifoldness
  (see §18).
- `save {path?}` — writes the project in its native format, with every
  parameter and structure — not the same thing as `export`. No `path`
  overwrites wherever it was opened from.
- `export {to, format?, force? (default false)}` — `format` defaults to
  `to`'s own extension; `force` writes anyway despite an error-level
  issue. The format list is generated straight from `builtInModelWriters`
  (§17).
- `import {path/bytes, unit?, upAxis? (default y), weld?, fixNormals?,
  triangulate? (all default false)}` — reads glTF, GLB, OBJ, `.f3d`, or
  STL; **FBX is recognised and explicitly refused with a reason**, not
  silently ignored. Each imported object is one undo step.
- `journal` — writes the session's own successfully-run command list as
  JSON Lines (`CommandJournal` shape) — not the project itself (`save`
  is).
- `cleanup` — welds duplicate vertices, removes zero-area faces, and
  outward-orients every closed shell, across the whole project, one undo
  step. Worth calling right after `import`.
- `makeGameReady {profile}` — triangulates every mesh, recalculates
  normals, and fits every image to the named budget (`desktop`/`mobile`/
  `web`), all in one step. The project's own profile is unchanged — this
  is a one-time fit to the named budget, not a setting change.
- `buildFrom {items[]}` — a batch of primitives as one undo step; each
  entry is `addPrimitive`'s own arguments plus an optional `name`/`parent`
  (an index into this same list, not an object id).
- `inspect` — metrics (object/vertex/face counts) plus issues in one
  call — `list` and `check` together, no picture.

---

## 15. Import and export formats

**Import** (`import` tool): glTF, GLB, OBJ, native `.f3d`, and STL. FBX is
recognised and refused with a reason, not silently dropped. Options mirror
the app's own import screen: `unit` (`mm`/`cm`/`m` — STL carries no unit
of its own, so this typically matters most there), `upAxis`, `weld`,
`fixNormals`, `triangulate`.

**Export** — the exact writer list
(`packages/flutter3d_formats/lib/src/model_writer.dart:263-270`):

```dart
const List<ModelWriter> builtInModelWriters = <ModelWriter>[
  F3dModelWriter(),
  GlbModelWriter(),
  ObjModelWriter(),
  StlModelWriter(),
  StlModelWriter(ascii: true),
  UsdzModelWriter(),
];
```

Native `.f3d`, binary `.glb`, `.obj` (+ `.mtl` when a material is present
— the only format producing two files), `.stl` (binary and ASCII, two
separate writers; requesting bare `"stl"` gets the binary one), and
**`.usdz`** (not mentioned by the older planning doc at all — it landed
later). There is no separate JSON `.gltf` + `.bin` writer — only `.glb`;
`export`'s own tool description says so directly. This directly overturns
`doc/model-editor.md`'s "no glTF/GLB, OBJ, or STL writers" row, which is
stale.

---

## 16. Headless render

`packages/flutter3d_model_mcp/lib/src/render_tool.dart` — both tools
return real MCP image content (PNG bytes), not a base64 string inside a
text block, backed by `CpuDevice` (the software rasterizer from
`flutter3d_cpu`, not a GPU).

- `render {view?, mode?, joint?}` — one picture. `view` ∈ `front`, `back`,
  `left`, `right`, `top`, `bottom`, or `iso` (three-quarter isometric,
  the default). Content-framed. An empty project is refused, not rendered
  blank.
- `renderSheet {mode?, joint?}` — **a 2×2 contact sheet: front, right,
  top, and iso, one image.** Not a six-camera rig — that phrase appears
  only in tutorial prose describing a hypothetical, unbuilt possibility,
  not this tool's actual output.
- Shading modes (`renderModes`): `material` (default, the project's own
  materials), `normals` (face colour = direction — an inside-out shell or
  an unwelded seam reads as a colour seam), `selection` (material plus
  the current selection highlighted orange, reads `session.history
  .selection` directly, no separate argument), `weights` (`joint`
  required — an unlit gradient of that joint's influence; anything not
  bound to it renders as plain material rather than falling through to
  nothing). **Wireframe is not implemented** — it waits on the engine's
  own edge-drawing landing, named honestly in the tool's own description
  rather than left silently unavailable.

---

## 17. Export readiness and budgets

`packages/flutter3d_model_core/lib/src/readiness.dart` — exactly two
severities, deliberately not a five-point scale ("a five-point scale is a
scale where every problem lands in the middle"): `warning` (will load,
but disappoints someone — over budget, an inside-out shell) and `error`
(will not load at all — an empty mesh, a zero-area face). An `ExportIssue`
with `object == null` is about the whole project (a shared budget spent by
everything at once — blaming "the biggest object" would not be honest).
The half-edge-level checks (self-intersection at a point, inside-out
shells, zero-area faces) live in `flutter3d_mesh`'s own `MeshChecks`;
`check`/`ExportReadiness` restate its results in terms of the object, not
a raw list of face ids.

`ProjectProfile` (`packages/flutter3d_model_core/lib/src/project.dart:53`)
— "a profile rather than a set of warnings, because the same model is
fine for one target and impossible for another": `name` (default
`'desktop'`), `target: ProfileTarget` (`desktop`/`mobile`/`web`),
`maxTriangles` (default 500,000), `maxJoints` (default 64, mirrors
`Skeleton.maxJoints`), `maxInfluences` (default 4), `maxTextureSize`
(default 4096), `maxTextureBytes` (nullable — nothing measures a total
yet), `requireTriangles` (default true), `requireManifold` (default
false), `textures: TextureBudget` (default `desktop`), `texelsPerMeter`
(nullable — one shared texel-density target across the whole project, or
no check), `fps` (default 30 — the time base keyframe commands assume),
`frameSnap` (default false). A built-in `ProjectProfile.mobile` constant
tightens `maxTriangles` to 100,000 and `maxTextureSize` to 2048.

---

## 18. Cabinet integration (cloud save-back)

`apps/flutter3d_modeler/lib/src/cabinet_link.dart` —
`CabinetLink.fromQuery` reads `id`, `mode`, `csrf`, `editable`, `sourceSha`
from the launch URL (alongside `model`/`name`, read separately for an
ordinary open). The full query shape `cloud/server`'s viewer page builds:
`/app/?model=...&name=...&id=...&mode=...&csrf=...&editable=...&sourceSha=...`.

`isFromCabinet = id != null`; `isViewOnly = mode == 'view'`;
`canSaveBack = isFromCabinet && !isViewOnly`; `shouldCapturePreview =
isFromCabinet && isViewOnly && isOwner && sourceSha != null &&
sourceSha.isNotEmpty` — all four conditions gate only the *UX* (whether
the app tries); the server independently re-checks ownership on every
POST regardless, and `CabinetLink` is explicitly documented as not itself
a security boundary.

Save-to-cabinet: `POST /api/v1/models/<id>/source`, headers `x-csrf`,
`x-filename: model.f3dproj`. Preview capture: `POST
/api/v1/models/<id>/preview`, headers `x-csrf`, `x-source-sha256`.

---

## 19. Platform notes

- `FLUTTER3D_WINDOW=WIDTHxHEIGHT` (an environment variable, not a
  `flutter run` CLI flag) sizes the macOS window at launch, read in
  `MainFlutterWindow.swift` before Dart's own `main()` runs — the only
  reliable way to get a fixed window size for a screenshot script.
- The macOS build is App Sandboxed
  (`com.apple.security.app-sandbox` + `.files.user-selected.read-write`):
  `import`/`export`/`save` can only reach a file a person picked through a
  real file dialog — an absolute path outside that throws
  `PathAccessException`, by sandbox design, not a bug.

---

## 20. Known gaps, as of this writing

- `ModelerMode.material` has no properties-panel sections of its own
  (§4) — material editing currently happens under Object mode.
- Mirror modifier: `bisect` is refused outright; `flipUv` is accepted but
  has no effect yet (§7).
- `setSceneLightingField`'s advertised schema does not list `bloomEnabled`
  as a valid `field`, even though the command underneath actually handles
  it — undocumented, working surface an MCP client would not discover
  from `tools/list` alone (§12).
- `renderSheet` is a 2×2 sheet (front/right/top/iso), not the six-camera
  rig some tutorial prose describes hypothetically (§16).
- Wireframe render mode is not implemented (§16).
- `ProjectProject.lighting` and `.simulationCache` are live in memory but
  not written to the saved file format (§1).
- No separate JSON `.gltf` + `.bin` writer, only `.glb` (§15); FBX import
  is refused, not supported.
- Cloth simulation baking requires a background job — there is no single
  synchronous MCP tool call for it (§13).
- `uv`, `sculpt`, and `render` modes are declared (`ModelerMode` values
  with icons and labels) but marked `ready: false` — not full workflows
  yet.
