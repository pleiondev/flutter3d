# The modeller against Blender, Maya, Flutter Scene Editor and OpenSpace3D — a critical UX analysis

Date: 2026-09-15. A follow-up to `docs/modeller-ux-review.md` (which holds our
own findings and the `ux-NN` backlog; this document covers where we stand
relative to others and what is worth adopting). References to code and to
`ux-NN` point to the same places.

## 0. The frame of comparison

The five tools belong to three different classes, and an honest comparison is
only possible dimension by dimension, not "overall":

| Tool | Class | Audience | Mesh editing | Agent / scripting | Platforms | Activity |
|---|---|---|---|---|---|---|
| **Blender** 4.x–5.x | general-purpose DCC: modelling, sculpting, UV, rigging, animation, rendering | from beginners to studios | the reference | Python API, countless add-ons, Blender MCP (third party) | Win/mac/Linux | weekly |
| **Maya** 2024+ | studio DCC, focused on rigging/animation | professionals | mature | MEL/Python, Script Editor with "Echo All Commands" | Win/mac/Linux | yearly |
| **Flutter Scene Editor** 0.22.1 | a **scene** editor for flutter_scene | Flutter developers | **none** (Cube and Sphere, `splitMeshByGrid`) | MCP with 40+ tools, `run_command` | macOS arm64 only | active (2026-08) |
| **OpenSpace3D** 1.96.1 | building interactive 3D/VR/AR applications without code | "citizen developers", education | **none** ("not a modeler") | PlugIT graph, Scol, ChatGPT-PlugIT | editor on Windows only | active (2026-07) |
| **Our modeller** | a modeller + game-ready pipeline for flutter3d | indie developer, pro modeller, agent | yes (half-edge, n-gons, extrude/loop cut/bevel/…) | MCP with 131 tools, shared undo with authorship | macOS + web (planned), tablet/phone shells built | active |

Two conclusions before any tables. First: in **modelling depth** we compete
only with Blender and Maya, and lose to them by definition — the question is
how far 20 % of their operations cover 80 % of game-ready tasks. Second: in
the **"editor ↔ runtime ↔ agent"** combination there is one direct
competitor — Flutter Scene Editor — and there the comparison is on equal
terms, tipping different ways on different dimensions.

Sources: Blender Manual (Industry Compatible keymap, Undo & Redo /
Adjust Last Operation) — https://docs.blender.org/manual/en/latest/interface/keymap/industry_compatible.html,
https://docs.blender.org/manual/en/latest/interface/undo_redo.html;
Maya Help (Application Home, Echo All Commands, crash recovery) —
https://help.autodesk.com/view/MAYAUL/2024/ENU/?guid=GUID-BA0DEED7-B0A4-4304-9A2B-DD3CAB0F688A,
https://help.autodesk.com/cloudhelp/2020/ENU/Maya-Scripting/files/GUID-B0E70A37-1585-4FA1-99EF-D680A9152E18.htm;
flutter_scene — the repository https://github.com/bdero/flutter_scene
(commit `77c7dbaae`, `packages/flutter_scene_editor*`,
`packages/flutter_scene_mcp/lib/src/tool_surface.dart`), https://fscene.dev/editor/;
OpenSpace3D — https://www.openspace3d.com/documentation/en/,
https://www.openspace3d.com/en/version-history/, the forum
https://forum.openspace3d.com/.

Scale in the matrix: **0** — none; **1** — basic; **2** — mature; **3** —
industry reference.

---

## 1. Matrix by dimension

| Dimension | Blender | Maya | Flutter Scene | OpenSpace3D | Us | Verdict |
|---|---|---|---|---|---|---|
| 1. First launch and onboarding | 3 | 2 | 1 | 1 | **0–1** | behind everyone except OS3D |
| 2. Navigation and input devices | 3 | 3 | 2 | 2 | **0–1** | the only one without trackpad orbit |
| 3. Selection and transforms | 3 | 3 | 2 | 1 | **1** | gizmo and modals below Flutter Scene |
| 4. Mesh editing | 3 | 3 | 0 | 0 | **2** | our trump card against the direct competitors |
| 5. Modifiers / procedural | 3 | 2 | 0 | 0 | **1** (core 2) | the core exists, the UI doesn't |
| 6. Materials and textures | 3 | 3 | 2 | 1 | **2** | on par with Flutter Scene in substance, minus the empty mode |
| 7. Rigging, weights, animation, retargeting | 3 | 3 | 0 (playback) | 1 (clip composition) | **2** | stronger than both direct competitors |
| 8. Scene, lighting, "in-game" preview | 3 | 3 | 3 | 2 | **1–2** | Flutter Scene is ahead: Play with hot reload |
| 9. Import/export, game-readiness | 2 | 2 | 1 | 2 | **2–3** | our trump card: readiness, profiles, budgets |
| 10. History, undo, journal, recovery | 3 | 2 | 2 | 1 | **2** (core 3) | the core is stronger than anyone's, delivery is broken (ux-01) |
| 11. Feedback: status, refusals, diagnostics | 3 | 2 | 2 | 1 | **2** | the texts are a reference, the presentation isn't |
| 12. UI customisation, command palette, keymap presets | 3 | 3 | 2 | 1 | **0** | no docking, no palette, no presets |
| 13. Extensibility and the agent | 3 (Python) / 1 (MCP) | 3 (MEL) / 0 | 3 (MCP) | 2 (PlugIT, ChatGPT) | **2** | 3 for safety and undo, 1 for scene overview |
| 14. Touch, accessibility, localisation | 1 / 2 / 3 | 0 / 2 / 3 | 0 / 1 / 0 | 0 / 0 / 2 | **1 / 2 / 1** | the only one with a phone shell; it doesn't get through a scenario |
| 15. Documentation and community | 3 | 3 | 1 | 1 | **1** | six tutorials without screenshots |

Below, dimension by dimension: what the others do, where we are, what to take.

---

## 2. By dimension

### 2.1 First launch and onboarding

**Blender.** A splash screen on every launch: New File from templates
(General, 2D Animation, Sculpting, VFX, Video Editing), Recent, Open, Recover
Last Session. On the **first** launch — "Quick Setup": choosing the keymap
(Blender / Industry Compatible), the select mouse button (left / right), the
spacebar action, the theme. One page of questions removes the keymap conflict
before it happens.

**Maya.** "Application Home" since 2022.1: Recent Files with paths, links to
the Learning Channel, What's New, project templates. Old Maya opened into an
empty scene — Autodesk moved away from that.

**Flutter Scene.** A start screen: Open project / New project / New scene /
Open .fscene / Import glTF + recent. No scene templates. The editor's
documentation is one page (download, requirements, build from source).

**OpenSpace3D.** No start screen; there are demo samples and "user level
filtering" in Preferences that hides rarely used PlugITs — the only one of the
five with an explicit user-level switch. A Quick Start video from 2011.

**Us.** We start with a cube that is immediately flagged with a warning; the
start screen exists but is hidden behind the ⌂ icon and bypasses the import
dialog (`ux-06`); nine of ten terms on buttons have no explanation; the
"Tutorial" link goes to the site root.

**Take.** Blender's Quick Setup as is (keymap, select button, theme) — this is
the answer to the "simple/pro" mode question; Maya's Home as a mandatory first
screen with Recent + the four scenario cards from the handoff (screen 20);
OS3D's "user level filtering" as a rule for progressive disclosure in panels,
not as a global mode.

### 2.2 Camera navigation and input devices

**Blender.** MMB orbit, Shift+MMB pan, wheel zoom; numpad 1/3/7 views;
`Emulate 3 Button Mouse` (Alt+LMB) and `Emulate Numpad` for laptops; trackpad —
two fingers orbit, Shift pan, Ctrl zoom; `.` frame selected, Home frame all; a
navigation gizmo with clickable axes.

**Maya.** Alt+LMB/MMB/RMB — the standard Unity, Substance and Marmoset adopted;
`F` frame selected, `A` frame all; ViewCube.

**Flutter Scene.** LMB-drag orbit, MMB or Shift+LMB pan, wheel zoom; trackpad:
two fingers orbit, Ctrl/Cmd zoom, Shift pan, pinch zoom; RMB held — WASD
free-look with Shift acceleration; `F` frame; an orientation gizmo and
orthographic views (`orbit_camera.dart`, `free_look_camera.dart`).

**OpenSpace3D.** LMB orbit, MMB pan, wheel zoom; Navigate / Walk modes
(third-person, arrow keys); on selection the camera moves to face the object.

**Us.** Orbit only with MMB or touch; trackpad → `idle`, `alt` is declared and
never read (`orbit_gestures.dart:370-380`); one finger on touch — a selection
box; `frameSubject` exists only in MCP. This is the most serious gap of all
dimensions: **all four** competitors orbit the camera from a MacBook trackpad,
we don't (`ux-04`).

**Take.** Flutter Scene's scheme as a whole (it is already designed for a Mac
without a mouse and for the same Flutter input): LMB orbit when no tool is
armed, two-finger orbit, RMB free-look for large scenes. Plus Alt+LMB, as in
Maya, for people coming from there. `F`/`.` for frame and numpad views.

### 2.3 Selection and transforms

**Blender.** `G/R/S` are modal from the first press: the cursor is captured,
`X/Y/Z` constrain, `Shift+X` — a plane, digits enter a value, a readout in the
viewport header shows "Dx: 0.35 m", an axis line runs through the scene, Ctrl
snaps, Shift gives precision, RMB/Esc cancel. The gizmo is optional and drawn
on top (no depth test). Pivot and orientation — the `.` and `,` pie menus.
Proportional editing with `O`. Box/circle/lasso select with a switch in the
toolbar.

**Maya.** `W/E/R` + the Universal Manipulator; the Channel Box for numbers
with LMB drag-scrub; soft select `B`; snapping — three toggles in the status
line (grid / curve / point) with `X/C/V` held; marking menus on RMB for
component selection.

**Flutter Scene.** Blender-style `G/R/S` with axis constraints and `Esc`;
Move/Rotate/Scale buttons; `TransformSpace { global, local }`; a pivot
selector for multi-selection "mirroring Blender's"; Ctrl/Cmd-click toggles.
No snapping found.

**OpenSpace3D.** An X/Y/Z gizmo, Tab cycles Move→Rotate→Scale, right-clicking
a button opens a numeric input dialog. No snapping, no modals, multi-selection
in 3D isn't described.

**Us.** The gizmo is hidden inside an opaque body and doesn't drag (`ux-03`);
the modal starts only after a drag begins, so `G`→`X` hits delete
(`transform_session.dart:124-134, 240-242`); the Pivot/Space chips don't
affect interactive transforms (`ux-12`); snapping is Ctrl with a hard-coded
step; the readout and axis line aren't built (`ux-11`). At the same time we
have what Flutter Scene and OS3D don't: box select with Shift/Ctrl rules,
byte-exact geometric snapping, a modal rolled back through a transaction.

**Take.** From Blender: the modal from the first press, the readout + axis
line, Shift precision, the pivot pie. From Maya: drag-scrub numbers and snap
toggles in the status line. Flutter Scene is the proof that Blender modals fit
a Flutter editor and require nothing exotic.

### 2.4 Mesh editing

**Blender / Maya.** The full set: knife, inset, bridge, edge slide, spin,
loop/ring/linked select, proportional editing, element hover highlight,
selection statistics in an overlay, "Adjust Last Operation".

**Flutter Scene / OpenSpace3D.** None. Both honestly call themselves scene
editors and send you to Blender for the model.

**Us.** Half-edge with n-gons, extrude/loop cut/bevel/dissolve/merge/separate/
fill holes/triangulate/normals/seams/unwrap; a last-operation card with
`amend` — functionally an analogue of Blender's F9, and done right. Missing:
knife/inset/bridge/edge slide (deliberately, `tools.dart:17-22`),
loop/ring/linked from the keyboard (the commands exist, the bindings don't),
hover highlight, lasso, the diagnose/repair block in the panel (`ux-16`).

**Verdict.** This is the only dimension where we are clearly ahead of both
direct competitors and clearly behind both DCCs. Strategically, the point is
not to chase Blender but to close the **game-ready minimum**: inset (for
panels and windows), bridge (for joining), edge slide (for adjusting loops),
loop select with Alt+click, diagnose + repair. Everything else a person will
do in Blender and import — and our import already handles that.

### 2.5 Modifiers and procedural workflows

**Blender.** A stack with three toggles (viewport / render / edit mode),
expanded parameters, drag reorder, Apply, Geometry Nodes.
**Maya.** Construction history + deformers, less visual.
**Flutter Scene / OS3D.** None.
**Us.** The core: array/mirror/smooth/subdivision/boolean with fields; the UI:
"Add" silently puts Mirror X, only the array's `count` is editable (`ux-13`).
The handoff (screen 24) drew two toggles — Blender suggests at least two are
needed (viewport / export).

**Take.** Blender's stack as is: a kind picker, expanded fields, two toggles, a
"triangles in → out" counter (that one is already our idea from the handoff;
Blender doesn't have it — worth keeping).

### 2.6 Materials and textures

**Blender.** Shader Editor (nodes) + simplified Principled BSDF panels; the
Material Preview viewport mode; an asset library.
**Maya.** Hypershade + Attribute Editor; Arnold preview.
**Flutter Scene.** `.fmat` files compiled on the fly, hot-swapped on file
change with GLSL include watching, "Open in editor" into an external editor;
`createMaterial`/`setMaterialType` through commands. No node graph in the UI —
a material is edited as a file.
**OpenSpace3D.** A material editor with Solid/Wire, two-sided,
ambient/diffuse/specular, normal and roughness/metalness by channel; IBL by
default since 1.95.
**Us.** A panel with a swatch, sliders, five slots, a collapsed graph of 11
nodes with baking, `.fmat` link/embed, Material Studio for preview. In
substance — on par with Flutter Scene and above OS3D. But the "Material" mode
is empty (`ux-07`), and "Add material" doesn't assign.

**Take.** From Flutter Scene — `.fmat` hot-swap by file watching (our
`linkMaterialFile` reads only once) and "Open in editor". From Blender — a
material preview on a sphere/cube right in the panel, not in a separate
dialog.

### 2.7 Rigging, weights, animation, retargeting

**Blender.** Armature, weight paint with a cursor, Dope Sheet + Graph Editor,
NLA, Rigify; retargeting through add-ons.
**Maya.** The reference: HumanIK with an editable bone map, Graph Editor, Time
Slider with zoom/scrub, ghosting.
**Flutter Scene.** Only playback of glTF clips; animation components without a
curve editor.
**OpenSpace3D.** Animation sequences — a timeline combining existing clips
(length/transition), no new clips created; a Blendshape PlugIT since 1.96;
Mixamo/Avaturn import.
**Us.** Auto-rigging from markers (humanoid/quadruped, fingers, IK, face),
weight painting as a command with ⌘Z, a bend bar, a timeline + curves, morphs
with drivers, retargeting with auto-map and lock feet, root motion. This is
clearly more than both direct competitors have. Weak spots: a timeline
without zoom/scroll/frame snapping, a read-only bone map, no brush cursor,
morphs that don't deform the mesh live (`ux-24`).

**Take.** From Maya: an editable bone map (a dropdown per row), wheel zoom and
scrub on the timeline, snapping to frames. From Blender: a brush cursor and
`[`/`]`. From OS3D: Mixamo import as a **scenario** in a tutorial (our
`looseAutoMap` already reads `mixamorig:`, but nobody tells anyone).

### 2.8 Scene, lighting and the "in-game" preview

**Flutter Scene** is the reference for our class here: a Play toolbar runs the
real application (`flutter run --machine`), Hot reload / Hot restart / Stop,
device and build configuration choice; `reload_scene` through the VM service;
the viewport is the same `SceneView` as in the game; a Stage panel with a
skybox, HDR/EXR environment, GI, TAA/SMAA/MSAA, DoF, fog, god rays, colour
grading; a Render Graph panel with passes and capture
(`list_render_passes`, `get_pass_output`, `scan_for_nans`).
**Blender / Maya.** Complete, but they don't show "in-game" — not their job.
**OpenSpace3D.** Play/Pause right in the editor, Launch in player F12,
Rendering PlugITs (Shadows, SSAO, HDR, Water).
**Us.** Scene mode: lights, shadows, four environment presets, bloom,
exposure; a Game preview screen with budgets; `LightingSync` into the headless
render. No HDR panorama import, no "run in the game" with hot reload, the panel
truncates labels and mixes languages (`ux-23`).

**Take.** Flutter Scene's Play toolbar is a direct candidate: flutter3d has
`apps/dungeon`/the platformer and the same renderer, so "open this model in a
game template and hot-reload it" is feasible. HDR/EXR import as an
environment. The Render Graph panel — not needed by a person, but
`list_render_passes` already answers "why is the frame dark" for an agent.

### 2.9 Import/export and game-readiness

**Blender.** glTF/FBX/OBJ/STL/USD both ways; no engine-readiness checks — those
are covered by add-ons and external validators.
**Maya.** Game Exporter (FBX), send-to-Unity/Unreal.
**Flutter Scene.** glTF import with scale/up axis/compress textures/"Link to
source" as a prefab; no export from the editor found (the glTF writer is in an
unmerged PR).
**OpenSpace3D.** 40+ formats through Assimp; export is whole applications
(exe/apk/iOS/XR), not models; no web export.
**Us.** Import of glTF/GLB/OBJ/STL/.f3d with units/axis/welding, FBX refused
with a reason; export to .f3d/.glb/.obj/.stl/.usdz; `check` with two severity
levels, desktop/mobile/web profiles with triangle/texture/bone budgets,
`makeGameReady`, `cleanup`, LOD that preserves UVs and weights. On
game-readiness we are ahead of all five — the strategic position from the
business plan ("the engine people actually ship on").

But the export dialog shows three formats of five writers, is duplicated by
two paths, and the start screen bypasses the import dialog (`ux-06`,
`ux-18`).

**Take.** From Flutter Scene: "Link to source" — import as a link to the
source file with Re-import (our import is always a copy). From Blender: an
export preview with "selection only" and "apply modifiers".

### 2.10 History, undo, journal, recovery

**Blender.** An Undo History menu, the Info editor logs every operator as
Python (`bpy.ops.mesh.extrude…`) — a command journal out of the box, Auto Save
every 2 minutes + Recover Auto Save / Recover Last Session, `quit.blend` on
exit.
**Maya.** Echo All Commands in the Script Editor (a MEL journal), Incremental
Save, Auto-save, crash recovery with a backup scene.
**Flutter Scene.** `EditHistory` with transactions and a History panel with
transaction chips ("Create node, Set transform, Add component…"); a gizmo drag
is one step; no autosave/recovery found.
**OpenSpace3D.** Undo/redo since 1.6.1 with no documented keys; no autosave or
recovery found; the forum complains about crashes on save.
**Us.** The core is stronger than everyone's: commands as values with `says`,
transactions, `amend`, `StepAuthor` with the agent's one-way undo, an
append-only JSONL journal with cold replay (checked on six tutorial cases), an
emergency autosave before the crash dialog, recovery that names the number of
objects. But autosave **doesn't write** (`ux-01`), and the history panel is
visible only inside Agent Session.

**Take.** From Flutter Scene: a History panel as an ordinary panel, not part of
the agent one; from Blender: an Undo History menu on clicking the undo button;
from Maya: Incremental Save as an option. And make what already exists
actually work.

### 2.11 Feedback: status, refusals, diagnostics

**Blender.** A status bar with context mouse hints (what LMB/MMB/RMB do right
now), Reports coloured INFO/WARNING/ERROR with history in the Info editor, a
statistics overlay.
**Maya.** Command Line + Script Editor history, HUD.
**Flutter Scene.** A Console panel, `get_console` for the agent, render
statistics.
**OpenSpace3D.** A Logs and Debug area as a separate window zone.
**Us.** Readiness in three tones, in words that name consequences — textually
better than Blender ("two pieces of surface meet at a point" instead of
"non-manifold"). But one line with an ellipsis, a refusal indistinguishable
from narration, an agent's refusal not shown to the person, no message history
(`ux-17`).

**Take.** From Blender: mouse button hints in the status line (solves "how do
I rotate the camera" without help); an Info/Console panel with a history of
messages and refusals — we already have `said`, only the feed is missing.

### 2.12 UI customisation, command palette, keymap presets

**Blender.** Workspace tabs, arbitrary area splitting, F3 operator search,
Quick Favorites `Q`, pie menus, three keymap presets and a keymap editor.
**Maya.** Workspaces, a Hotbox on the spacebar, marking menus, a Hotkey Editor
with profiles.
**Flutter Scene.** Docking on `multi_split_view`: panels into tabs/splits,
detachable into separate OS windows, the layout is saved, multiple viewports;
Cmd+P — a command palette (`search_commands` is available to the agent too).
**OpenSpace3D.** Detachable windows since 1.85, a Theme editor.
**Us.** Nothing: a fixed 250-wide panel with no splitter, one viewport, no
palette, one keymap. This is the second most severe gap after navigation — and
the easiest to close, because Flutter Scene has already shown which packages
do this in Flutter.

**Take.** A Cmd+P/F3 command palette — we have a command table with `says`, so
the palette is almost free and solves discoverability for a beginner along
the way. A panel splitter and collapsing (`N`/`T`). Blender/Maya keymap
presets. Docking — later, and only if a second viewport appears (retargeting
and LOD already ask for one).

### 2.13 Extensibility and the agent

| | Blender MCP | Flutter Scene MCP | OpenSpace3D | Us |
|---|---|---|---|---|
| Transport/security | TCP without a token | TCP 127.0.0.1:7007 + stdio bridge, no token | ChatGPT-PlugIT outward | loopback + a token per launch |
| Editing | `execute_blender_code` (Python) | `run_command` over the editor's command palette | PlugIT graph | 120 typed commands |
| Undo/authorship | none | every command is a step, "identical to the editor UI" | none | a step with an author, undo only one's own |
| Scene overview | `get_scene_info`, `get_object_info` | `describe_scene` (a tree with slash paths), `get_node`, `get_selection` | — | `list` without transforms, `inspect` counters |
| Picture | live viewport | `screenshot_viewport`, `screenshot_window` | — | headless `render`/`renderSheet` in 4 modes |
| Render diagnostics | none | `list_render_passes`, `get_pass_output`, `scan_for_nans`, `get_render_stats`, `list_draws`, `list_shaders` | — | none |
| Runtime | none | `run_project`, `hot_reload`, `reload_scene`, `get_console`, `list_devices` | Play/F12 by hand | none |
| Reference | `describe_node_type`, `bpy_api_lookup` | `list_component_types`, `describe_component_type` | PlugIT help | "read the subtypes" references |
| Prompts | `asset_creation_strategy` | none | — | none |
| Assets | PolyHaven/Sketchfab/Rodin | `import_model`, `import_environment` | 40 formats | local `import` |

**Verdict.** On **safety and reversibility** we are better than all four. On
**state overview** — worse than Flutter Scene and Blender MCP: the agent can't
read transform, material, version or element ids (`ux-19`). On **connection
to the runtime**, Flutter Scene has shown what we don't have at all.
Separately: Flutter Scene opened the whole editor palette to the agent with a
single `run_command` — the same "one table for the person and the agent"
principle we have, except theirs reached the UI, while our UI actions are
limited to seven `ui.*`.

**Take.** `describe_scene`/`get_node` (= `describe` from `ux-19`),
`screenshot_viewport` as `ui.screenshot`, `describe_component_type` for
`TextureNode`/`ParametricShape`/modifiers, `run_command` over a shared
palette, `get_console`. From Blender MCP — a strategy prompt and an asset
source.

### 2.14 Touch, accessibility, localisation

**Blender.** Touch — minimal (a tablet pen for sculpting); screen reader —
none; localisation — 30+ languages.
**Maya.** Touch — none; localisation — yes.
**Flutter Scene.** macOS only; no touch; no localisation found; a `forui` +
Material theme.
**OpenSpace3D.** The editor is Windows only; deploys to mobile and XR;
localisation EN/FR.
**Us.** The only ones with tablet and phone shells and a `ui-23` semantics pass
— but one-finger orbit is unavailable, Animation on the tablet is empty,
dialogs don't fit (`ux-21`); localisation ~25 % and two languages in one panel
(`ux-22`).

**Verdict.** Here we could be first, because none of the four even try. But
"built" ≠ "gets through a scenario". Until the phone shell takes a person
through "opened → painted → GLB", it is more honest not to show it in
marketing.

### 2.15 Documentation and community

**Blender / Maya.** Full manuals, thousands of tutorials.
**Flutter Scene.** One page about the editor, 40+ engine examples, an
`AGENTS.md` with skills for agents — documentation for the agent before
documentation for the person.
**OpenSpace3D.** Many short pages, a paid eBook, a forum with answers from the
author, outdated tutorials (2011–2017), the author himself admits he "forgot
to upload the updated doc".
**Us.** Six tutorial cases, each a reproducible `.jsonl` in CI (nobody else
has this), but every interface screenshot is a placeholder, completion time
isn't measured, and the "Tutorial" link goes elsewhere.

**Take.** From Flutter Scene — `AGENTS.md`/skills: a description of how an
agent should work with our MCP, kept in the repository. From OS3D — a
counter-example: documentation that lags behind releases loses trust faster
than no documentation at all.

---

## 3. What to borrow: a prioritised list

Cost: S — days, M — weeks, L — months. Linked to the
`docs/modeller-ux-review.md` backlog.

| # | Borrowing | From | Cost | Backlog |
|---|---|---|---|---|
| 1 | Navigation scheme: LMB/two-finger orbit, Shift pan, RMB free-look, `F` frame, Alt+LMB | Flutter Scene + Maya | S | ux-04 |
| 2 | Quick Setup on first launch: keymap, select button, theme; a Home screen with Recent and cards | Blender + Maya | M | ux-06, ux-37 |
| 3 | Modal `G/R/S` from the first press, readout, axis line, Shift precision | Blender | M | ux-11 |
| 4 | The gizmo over geometry, a working drag | Blender (and common sense) | S | ux-03 |
| 5 | A Cmd+P/F3 command palette from the command table; the same palette for the agent through `run_command` | Blender + Flutter Scene | S | ux-19, ux-37 |
| 6 | `describe`/`get_node`, `ui.screenshot`, `describe_component_type`, `get_console` | Flutter Scene | M | ux-19 |
| 7 | A History panel as an ordinary panel; Undo History on click | Flutter Scene + Blender | S | ux-05 |
| 8 | A Play toolbar: open the model in a game template with hot reload | Flutter Scene | L | a new row |
| 9 | Modifier stack: picker, fields, two toggles | Blender | M | ux-13 |
| 10 | Mouse button hints in the status line; a Console/Info message feed | Blender | S | ux-17 |
| 11 | Drag-scrub numbers, snap toggles in the status line | Maya | M | ux-15, ux-11 |
| 12 | `.fmat` hot-swap by file watching, "Open in editor" | Flutter Scene | S | a new row |
| 13 | An editable bone map, timeline zoom/scrub | Maya | M | ux-24 |
| 14 | "Link to source" import + Re-import | Flutter Scene | M | ux-18 |
| 15 | A strategy MCP prompt, `AGENTS.md`/skills in the repository | Blender MCP + Flutter Scene | S | ux-19 |
| 16 | HDR/EXR import as an environment | Flutter Scene | M | ux-23 |

---

## 4. What not to borrow

- **Blender MCP's `execute_code`** — it breaks undo, the journal and
  authorship, which work for us; `batch` in one transaction covers the need.
- **Maya's Hotbox and marking menus** — they require spatial memory and an RMB
  culture an indie developer doesn't have; a command palette solves the same
  problem with no learning.
- **A global user level like OpenSpace3D's** — it hides features; instead,
  Quick Setup and progressive disclosure (see `docs/modeller-ux-review.md`
  §7).
- **A material as a file with no panel (Flutter Scene)** — right for a Flutter
  developer with an IDE, wrong for a modeller; our panel is already better,
  hot-swap is needed as an addition.
- **A single platform (Flutter Scene — macOS arm64, OS3D — Windows)** — both
  competitors gave up cross-platform support; web + macOS + touch remains our
  distinction, if the touch shells are finished.
- **Documentation ahead of releases without updates (OS3D)** — our gap journal
  and `.jsonl` tutorials in CI protect against exactly that; pages with
  "screenshot pending" must not be published.

---

## 5. Positioning, in conclusion

Of the five tools, **only ours** combines three things: mesh editing,
engine-readiness checks with profiles, and an agent that shares one undo stack
with the person. Blender and Maya give the first, Flutter Scene the third plus
a connection to the runtime, OpenSpace3D code-free application assembly. The
niche is real: "bring someone else's model to a game-ready state, paint it,
rig it, check the budgets and export — by hand or with an agent".

What prevents taking it today, in decreasing order:

1. **Input** — orbit, the gizmo, modals (dimensions 2–3). Without them a pro
   modeller leaves in five minutes, and a beginner doesn't understand how to
   rotate the model.
2. **Delivery reliability** — autosave, "Scene" in debug, the session wedging
   after a failed GPU upload (`ux-01`, `ux-02`, `ux-08`).
3. **Overview for the agent** — without `describe` and transforms in `list`,
   the agent works blind, and the "MCP with undo" advantage isn't realised.
4. **The first screen and the Material mode** — what is visible in the first
   minute.
5. **Connection to the runtime** — the one place where Flutter Scene is
   strategically ahead and where we have all the parts (game templates, the
   same renderer), but no button.

Everything else — modifiers, the timeline, touch, localisation — matters, but
doesn't change the answer to "why open this editor instead of Blender".
