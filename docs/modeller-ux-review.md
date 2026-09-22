# The modeller — a combined UX and usability review

Date: 2026-09-15. Branch `modeler-ui`, commit `32874bd6`.

*Read this as the review it was on that day. All 54 `ux-NN` rows it produced
are done in `doc/plan-status.json` as of 2026-09-18, so a finding below is a
description of that commit and not of the tree: the tool count it gives, 131,
is 147 now, and most `path:line` references have moved.*
The third document next to `docs/modeller.md` (what exists) and
`docs/modeller-ux.md` (why it is that way): this one is about how comfortable
it is to use, for whom, and what to change first.

## 0. How the review was done

Four lenses, each against the actual code of `apps/flutter3d_modeler` and
`packages/flutter3d_model_mcp`, with every `path:line` reference checked:

1. **A beginner** — an indie game developer on flutter3d, not a modeller.
2. **A professional modeller** — coming from Blender (the main reference),
   Maya/3ds Max, with an eye on Unity/Godot.
3. **An agent over MCP** — an LLM client as the third user, plus a comparison
   with Blender MCP (`ahujasid/blender-mcp`).
4. **Adaptivity and accessibility** — tablet, phone, screen reader, contrast,
   localisation.

Plus a **live run** on macOS: debug and profile builds, a 1352×848 window,
driven through `--dart-define=mcpPort=0` (131 tools in `tools/list`),
screenshots with `screencapture -l`, clicks with `cliclick`. The run produced
findings the code does not show and refuted one hypothesis. What was **not**
checked live: the tablet and phone shells (the `FLUTTER3D_WINDOW` variable did
not change the window size when the binary was launched directly — the window
stayed 1352×848), touch and pen, and keyboard scenarios (`G`→`X`, `⌘Z`, `?`
through `cliclick` had no observable effect — most likely focus; conclusions
about keys below come from the code).

Severity scale: **critical** — stops work or breaks trust; **important** —
irritates regularly, can be worked around; **minor** — a rough edge.

---

## 1. Summary

1. **The UX foundation of the architecture is strong and worth protecting**:
   a command as a value with a `says` phrase; one tool table feeding the rail,
   the keys, help and MCP; a last-operation card through `amend`; a refusal as
   an offer rather than an exception; step authorship and one-way undo for the
   agent; readiness in three tones, with words that name consequences instead
   of terms. Blender MCP has none of this.
2. **But the first hour with the app breaks at the door.** The default cube
   arrives with an export warning; the start screen and "Recent" skip the
   import dialog; import defaults (metres, no welding) contradict the
   tutorial; "Material" mode is empty; the gizmo is invisible in the default
   display mode and does not drag with the mouse; on a MacBook trackpad the
   camera cannot be orbited.
3. **Reliability undermines trust more than any UI detail.** Live: autosave
   does not write at all (52 failures within minutes, "autosave: could not
   write" in the status line, while the crash dialog promises "autosave was
   written"); in the debug build entering "Scene" takes the whole UI down;
   importing `RobotExpressive.glb` over MCP "wedges" the session so that every
   following call returns a raw stack trace.
4. **The Agent Session panel and the Contact Sheet take a third of the screen
   whenever the MCP port is open**, even with no client connected. This should
   be collapsible and appear only once a client actually connects.
5. **For a professional modeller the main walls are not missing features but
   input**: orbit, the gizmo, modal transforms without a readout or an axis
   line, snapping without modes, a keymap that conflicts with both schools,
   number fields without scrubbing or expressions, a flat outliner.
6. **For an agent the main walls are state it has nowhere to read**: mesh
   element ids are never exposed, `list` shows no transform/material/version,
   a command's answer does not return the id it created, hidden selection
   makes calls order-dependent, and a wrong argument type is a mute refusal.
7. **Tablet and phone are built but do not get through an end-to-end
   scenario**: one-finger orbit is unavailable, "Animation" on the tablet is an
   empty screen, fixed-size modal dialogs don't fit, and there is no document
   name or unsaved marker.
8. **Localisation is at ~25 %**, and a single "Scene" screen mixes Russian
   headers with English fields.
9. **A global "simple/pro" switch is not needed.** What is needed: keymap
   presets, progressive disclosure inside panels, and hiding modes that aren't
   ready (§7).
10. The `docs/modeller.md` documentation disagrees with the code in four
    places (§9).

---

## 2. What the live run confirmed

These findings come from the running app and take precedence over
conclusions "from the code".

### 2.1 Critical

| # | Finding | Observation | Where in code | Recommendation |
|---|---|---|---|---|
| L1 | **Autosave does not work** | 52 log lines `storage: could not write autosave/… Application Support/flutter3d_modeler/autosave/….new (No such file or directory)` within a few minutes. The status line shows "autosave: could not write" with no explanation and no action. Meanwhile the crash dialog says "An emergency autosave was written, so the last edits should not be lost" — a promise that is false in this situation | `autosaving.dart:108`; `crash_handling.dart:152-156`; the `Application Support/flutter3d_modeler/` directory exists, `autosave/` inside it does not | Create the directory recursively before the first write; in the status line — "Autosave is not working: <reason>" with a "Show folder" button; the crash dialog must tell the truth ("autosave failed, save now") |
| L2 | **Debug build: "Scene" takes the UI down** | Switching to `scene` mode → Flutter assert "ListTile background color or ink splashes may be invisible" → a `CrashDialog` over a black screen. "Dismiss" doesn't help: dialogs pile up one per frame. MCP keeps answering "mode set to uv" to a dead screen. No assert in the profile build | the properties panel is wrapped in a `ColoredBox` (`shell.dart:165-168`), with `ListTile`/`SwitchListTile` inside (`scene_source_panel.dart:91,148`, `scene_shadows_panel.dart:45`, `scene_post_panel.dart:42`) | Wrap the panel in `Material` instead of `ColoredBox` (or `ListTile.tileColor`); in `CrashDialog` — deduplicate identical errors and show one dialog per session; a `shell_test` that enters every `ready` mode |
| L3 | **The gizmo is invisible in the default display mode and does not drag with the mouse** | With the cube selected and Move armed in "Material" display, there are no arrows — they are drawn with a depth test inside an opaque body; visible only in "Wire". Dragging the X arrow with the mouse: "You · move" appears in history, the object doesn't move (the field shows a truncated "-0.0("), the selection is dropped | `modeler_viewport.dart:688-695` (`_down` returns before registering `_pressed`), `:765-806` (`_move` requires `start != null`), `:878-887`; drawing in `_buildGizmo` `:497-527` | Draw the gizmo over geometry (no depth test, or a second pass); register the press in `_down` and carry the drag through to `onDragDone`; a test over the event stream, not only the `grabbedGizmo` arithmetic |
| L4 | **Importing `RobotExpressive.glb` over MCP "wedges" the session** | The `import` answer: `Exception: DeviceBuffer creation failed` with a stack; **every** following call (`list`, `ui.setMode`, …) returns the same stack, because `agentToolCalled` re-syncs the scene and throws again. The object is in the document (5505 △, 4 materials in the status line), not in the viewport; the person is shown nothing; "Bones 0 · actions 0" — neither the rig nor the clips arrived | `gpu_device.dart:414` → `device_mesh.dart:106` → `scene_sync.dart:147` → `modeler_cubit.dart:218` → `files.dart:200` | `SceneSync.apply` must catch the failure to load one object, mark it "could not be shown" and not take the rest down; in MCP — an offer-style refusal, not a stack; investigate the cause itself (an empty primitive? a skinned layout?) |
| L5 | **Agent Session and Contact Sheet are always on if the port is open** | The "Agent session" column and the sheet "CONTACT SHEET · No render/renderSheet call yet this session" take the right column and ~30 % of the viewport's height from the first frame, before any connection. The owner's remark during the run: "I don't understand why I need to see Agent Session and Contact Sheet all the time" | `ready_parts.dart:522-528, 554-556, 563-564`; `shell.dart:171-181` | Show the panel only after a client's first `initialize`; collapse it into a badge icon in the top bar with the call count; the contact sheet is a tab inside the panel, not the `bottom` slot |
| L6 | **"Material" mode is empty** | The button is enabled and switches to a screen with Display/View/Budget and nothing else; materials are edited in Object mode. No hint, no link | `tools.dart:65` (`ready: true`), `properties_sections.dart:56-61, 118` | Until a workspace exists — either `ready: false` with a tooltip, or show the `materials` section in this mode too |

### 2.2 Important

| # | Finding | Observation | Where | Recommendation |
|---|---|---|---|---|
| L7 | The default project greets you with a warning | The cube at launch: "exports with a warning: "cube" has 6 faces with more than three sides…", cut off with an ellipsis; a beginner thinks something is broken | `files.dart:96-97`, `status_line.dart:153-161` | A triangulated starting cube, or no quad warning for glb (the exporter triangulates them anyway); a tooltip with the full text |
| L8 | "opened in 4 ms" — a permanent developer chip in the viewport corner | Visible for the whole session | `ready_parts.dart` (the metrics overlay) | Show for 2 s and remove, or only behind a flag |
| L9 | The mode switcher is 8 unlabelled icons; three "not ready" ones look active | The handoff asks for a `SegmentedButton` with the text «Объект/Меш/Материал/Анимация/Сцена» (Object/Mesh/Material/Animation/Scene). `ui.setMode uv` over MCP answers "mode set to uv" — `ready: false` doesn't prevent the switch | `shell.dart:314-343`, `mcp_ui_actions.dart` | Labels (or tooltips); hide or disable unready modes both in the UI and in `ui.setMode` |
| L10 | "Scene": two languages in one panel, and truncated labels | «ИСТОЧНИКИ», «ТЕНИ», «Тени», «Источников 1 · теневых 0 из 6» (Sources, Shadows, "1 source · 0 of 6 shadowed") are in Russian; "Bloom", "None" and the fields are in English; the `Ambient`/`Exposure` field labels are cut to "Am"/"Ex po" (the label column is too narrow). A light is added at the origin inside the cube; the rail is empty | `scene_*_panel.dart`, `scene_environment_panel.dart` | One language per panel; label above the field; a new light above the scene (by its bounds), with a visible icon |
| L11 | The "Add" menu shows raw keys | `box`, `plane`, `sphere`, `cylinder`, `torus` in lowercase | `top_bar_actions.dart:101-106` | Human-readable labels with icons |
| L12 | Export: only `.f3d/.obj/.glb` | STL (binary/ASCII) and USDZ writers exist but aren't in the dialog; "Bake node transforms" without explanation | `export_screen.dart`, `model_writer.dart:263-270` | The format list from `builtInModelWriters`; a subtitle on the checkbox |
| L13 | An STL imported over MCP becomes an object called "node 0", scale shown as "0.00" | Unit `mm` → scale 0.001, the Scale field rounds to two digits and reads as zero; the name isn't taken from the file | `import_plan.dart`, `transform_rows.dart` | Name from the file; fields with adaptive precision |
| L14 | Material count: "1 materials" | The status line doesn't pluralise | `status_line.dart` | Pluralisation through `intl`, together with localisation |
| L15 | The window title is "flutter3d_modeler" | The document name and the "•" marker are only in the top bar | `MainFlutterWindow.swift`, `shell.dart:239-246` | Window title = document name, `isDocumentEdited` |
| L16 | "Save" is always the filled primary button, "Open"/"Import" are text without tooltips | The difference between Open (replace) and Import (merge) is invisible | `top_bar_actions.dart:110-117` | Save filled only when `isDirty`; tooltips; a "File" menu |
| L17 | `ui.openDialog autorig/preview` refuses: "not built in this app yet" | `docs/modeller.md` §4 promises four dialogs | `mcp_ui_actions.dart` | Build them, or drop them from the tool description and the documentation |
| L18 | `select {ids:[1]}` — a silent "success" with "nothing selected" | The schema expects `objects`; an unknown key isn't rejected | `model_tools.dart:2326-2362`, `tool_table.dart:76-98` | Argument validation against the schema (§5) |
| L19 | The UI submode ≠ the document level for the agent | `ui.setSubmode face` + `selectAll` selects the object, not faces; `extrude` answers "no faces are selected" | `tools.dart:115`, `selection.dart:34` | `ui.setSubmode` should also set the document's `ElementLevel`, or `selectAll` should take a `level` |
| L20 | "Wire" shows triangulation diagonals | A cube made of quads looks sliced | `display_modes.dart` | Draw `EditMesh` edges, not GPU triangles |
| L21 | Morphs: "No shape keys on this object" under the VIEW header | The message landed in the wrong section | `properties_sections.dart`, `morphs_panel.dart` | Its own "MORPHS" header |

### 2.3 A refuted hypothesis

The "pro" lens hypothesis that the agent's contact sheet pushes the timeline
out in animation mode **was not confirmed**: in the Pose submode the bottom
slot is taken by the timeline (`ready_parts.dart:529-556`), and the sheet only
appears where a mode has no bottom of its own.

---

## 3. The "beginner" lens

Persona: an indie developer with the task "opened a scan → painted it → GLB".

### 3.1 The "STL → GLB" path, by the code

1. Launch — a cube and a top bar of ten buttons, no start screen
   (`files.dart:96-97`); it is a dialog behind the ⌂ icon
   (`start_screen.dart:4-11`). Tutorial step 1 describes the start screen as
   the first thing — a mismatch.
2. Opening a file — three doors with different behaviour:
   - "Open" in the top bar → picker → the import screen;
   - ⌂ → "Open file" → picker → **no import screen**
     (`files.dart:881-927`, `:933-965` call `openBytes` directly): metres, no
     welding, the object 1000 times too large and without topology;
   - drag-and-drop → the import screen (`files.dart:1014-1022`).
3. The import screen — `_unit = metres`, `_weld = false`
   (`import_screen.dart:76-78`), although `ImportPlan` defaults to
   `weld = true` (`import_plan.dart:57`), and the tutorial says "mm" and
   "leave weld on".
4. Diagnosis — a one-line warning with an ellipsis; the tutorial's "Clean up"
   isn't on the rail.
5. Material — stay in Object (don't press "Material"); "Add material" creates
   one but doesn't assign it (`interactions.dart:223`); tapping the row again
   removes the material (`material_panel.dart:153`).
6. Export — `⌘E` or a click on the status line opens the full screen; the
   "Export" menu in the top bar is a different, cut-down dialog
   (`top_bar_actions.dart:126-144`, `files.dart:687-691` admits the
   duplicate). The result is "wrote N bytes to …"; warnings after a `\n` are
   invisible (`files.dart:745-748`).

In total 12–14 interactions and 4 dialogs on the right path; the path through
the start screen is shorter and gives a wrong result without a single warning.

### 3.2 Findings

| Severity | Finding | Where | Recommendation |
|---|---|---|---|
| critical | The start screen and "Recent" skip the import screen | `files.dart:881-927, 933-965` vs `:322-364`; the comment at `:872-880` refers to a refactor that doesn't exist | Both paths through `_openBytes` |
| critical | Import defaults contradict the tutorial | `import_screen.dart:76-78`, `import_plan.dart:57` | Unit by format (STL → mm), weld on, a plausibility hint under Bounds ("0.01 × 0.01 × 0.008 m — looks like millimetres?") |
| critical | An object imported without welding is a dead end | `mesh_commands.dart:58-62`, `object_commands.dart:355-358` | A "Build topology" command in Object mode; a refusal that names it |
| important | Refusals are indistinguishable from narration and get cut off | `modeler_cubit.dart:145-148`, `status_line.dart:153-161` | `warn` tone for refusals, a tooltip with the full text, a snackbar for multi-line ones |
| important | Mesh mode on a parametric/imported object is a silent void | `modeler_cubit.dart:531-535`, `ready_parts.dart:375-377` | A "Convert to a mesh (B)" banner on entry |
| important | Shortcut help doesn't teach the camera or the application | `shortcut_help.dart:32-40`, `modeler_keys.dart:76-91` | Camera/Application/Selection sections; an "⌘-drag to orbit" hint on first launch |
| important | The "Tutorial" link goes to the site root | `shortcut_help_screen.dart:25` | `/learn/modeler/` |
| important | Terms without explanation (table §3.3) | `shell.dart:444-446` (tooltip = `label · KEY`) | A second sentence in the tooltip, subtitles on checkboxes |
| important | Two export dialogs | `top_bar_actions.dart:126-144`, `files.dart:760-783` | The "Export" menu opens the screen with the format preselected |
| important | Save: an extra "Save without history" dialog, probe diagnostics in the message, no ⌘S | `files.dart:567, 591-602`, `modeler_keys.dart:107-133` | ⌘S; the history checkbox becomes a setting; the `p0-13n` probe text only behind a flag |
| important | Delete/Backspace don't delete | `tools.dart:272-278` | Bind both |
| important | "Add" in the modifier stack silently adds Mirror X | `ready_parts.dart:194-199`, `modifier_stack_panel.dart:51-63, 110-119` | A kind-picker menu, a fields card |
| minor | Localisation is half done; `sectionDisplay…` keys exist in `arb` but aren't read | `properties_panel.dart:428-706` | See §6.4 |
| minor | The project profile is explained nowhere | `start_screen.dart:92-99`, `properties_panel.dart:706` | A subtitle with the limits, a "Change…" button next to Budget |
| minor | Assigning a material is a tap on a row that toggles | `material_panel.dart:153` | "Add material" assigns to the selection; unassigning is a separate item |

### 3.3 Terms without explanation

| Term | Where | Hint |
|---|---|---|
| Lathe | `tools.dart:254`, `lathe_dialog.dart:149` | none |
| Bake (node transforms, 2048²) | `export_screen.dart:147`, `app_en.arb:86` | none |
| n-gon | `import_screen.dart:188` | none (readiness says "more than three sides" — good) |
| Manifold | not shown; readiness says "two pieces of surface meet at a point" | the term is replaced by its consequence — a model to follow |
| Weld coincident vertices | `import_screen.dart:167-171` | present, but "builds real mesh topology" is also a term |
| Extrude, Loop cut, Bevel, Dissolve, Merge by distance, Separate, Recalculate/Flip normals | `tools.dart:311-371` | only `label · KEY` |
| Apply the transform, Origin to the bottom, Convert to a mesh | `tools.dart:245-271` | none |
| Profile (desktop/mobile), KTX2, tex/cm, "MB of", △ | `start_screen.dart:96`, `export_screen.dart:159`, `status_line.dart:193-218` | none |
| Metallic/Roughness/Emissive/Alpha cutoff/Normal scale/Occlusion/Double-sided | `material_panel.dart:208-404` | none |
| Pivot/Space (Median/Individual, Global/Local) | `properties_panel.dart:506-508` | none |
| Socket | `object_row.dart:56` | none |

### 3.4 What to keep

- A file that can't be read never replaces the document
  (`files.dart:510-516`, `opening.dart:135-163`).
- Readiness in three tones, "(and N more)", errors offering "Export anyway"
  with named problems and "Show" for the object (`readiness.dart:141-147,
  438-441`, `export_screen.dart:189-262`).
- The last-operation card: a slider plus a field, `amend` instead of a new
  step, the close button ≠ undo (`operation_card.dart:79-135`).
- Undo covers selection too, and the tooltip says exactly what it will undo
  (`interactions.dart:180-186`, `undo_redo_buttons.dart:4`).
- The extrusion step is a tenth of the model's diagonal
  (`tool_commands.dart:61-82`).
- Recovery names the number of objects; a crash offers "Report a problem"
  prefilled (`restore_autosave_dialog.dart:14-34`, `crash_handling.dart`).
- Shortcuts don't fire into a text field (`modeler_keys.dart:150-157`); Lathe
  has a live preview and a disabled button with fewer than 2 points
  (`lathe_dialog.dart:97-114, 238-247`).

---

## 4. The "professional modeller" lens

### 4.1 Critical

| Finding | Where | Recommendation |
|---|---|---|
| **On a MacBook trackpad the camera cannot be orbited.** Orbit is `touch` only, or a mouse with a middle button; `trackpad` → `idle`; a two-finger scroll pans, with Ctrl zooms; `alt` is declared and never read | `orbit_gestures.dart:86-95, 329-338, 370-380` | Alt+LMB = orbit (Maya/Unity, Blender's "Emulate 3 Button Mouse"); two fingers = orbit, Shift = pan; a setting |
| **The gizmo** — see L3 | | |
| **Gizmo hit-testing doesn't depend on the view (move/rotate/scale)**: rotation rings (radius 82 px) overlap the arrow boxes; the uniform-scale centre cube is drawn but can't be grabbed | `modeler_viewport.dart:515-522, 827-839`, `gizmo_handles.dart:208-249`, `transform_gizmo.dart:79-83` | Separate hit objects for the rings and the centre |
| **The Pivot/Space chips don't affect interactive transforms** — only typed numbers | `transform_session.dart:409-430` vs `transform_dispatch.dart:59-101` | Pass `_pivot`/`_space` into `TransformSession` and `TransformElements` |
| **`G` → `X` deletes the selection** (by the code): the modal opens only on the first movement with LMB held, and until then `X` falls through to `object.delete`/`mesh.delete`. Not reproduced live (keys through `cliclick` had no effect) | `transform_session.dart:124-134, 240-242`, `tools.dart:272-278, 372-378` | `G/R/S` open the modal at once and capture the mouse, or an "armed" state intercepts `X/Y/Z` |
| **The morph slider doesn't deform the mesh in the viewport** — only the markers move | `ready_parts.dart:295-299` | `SceneSync` reads `shapeSet.weights` |

### 4.2 Important

| Finding | Where | Recommendation |
|---|---|---|
| No ⌘S | `modeler_keys.dart:75-91` | Add it |
| No Tab (Object⇄Mesh), numpad views or "frame selected"; `F` is taken by Flip normals | `shell.dart:314-343`, `tools.dart:365-371`, `mcp_ui_tools.dart:108` | Tab, `.`/Home, numpad 1/3/7; Flip → Alt+N |
| The keymap conflicts with both schools: `A` = Add box in object mode, so select-all isn't bound there; `O`/`Y`/`L`/`B`/`C`/`V`/`T` are taken in non-Blender ways | `tools.dart:230-378`, `selection_key_bindings.dart:30-31` | Keymap presets Blender/Maya/own (as in Godot/Unity) |
| Snapping is only Ctrl-hold with a hard-coded 0.1 m/15° step; no mode chips from handoff §02; no Shift precision | `transform_modal.dart:131-133`, `transform_session.dart:179-181` | Snap-mode chips in the viewport, the step in settings |
| The modal readout and the axis line aren't built; rotation = `dx * 0.01` rad/px rather than an angle around the pivot | `transform_session.dart:150, 396` | A "Move · X · 0.35 m" readout + Shift/Ctrl/Esc hints; angular rotation |
| The "Diagnose and repair" block (handoff §02) isn't implemented; `FillHoles` only over MCP | `properties_panel.dart:694-703` | Four rows that jump to the element, with repair buttons |
| Selection: no loop/ring/linked/grow from the keyboard or with Alt+click; no lasso, no hover highlight | the commands exist in core, the bindings don't | Alt+click loop, Ctrl+Alt ring, L linked, Ctrl+± grow/shrink |
| Modifier stack: only Mirror X and the array's `count`; no booleans on the rail | `ready_parts.dart:194-199`, `modifier_stack_panel.dart:93-119` | A kind picker, fields per kind, a second "on export" toggle (handoff §24) |
| The outliner is flat: no hierarchy, visibility, lock, rename on double-click, multi-select | `object_row.dart`, `ready_parts.dart:168-178` | A tree by `parent`, eye/lock, Shift/Ctrl |
| Number fields without drag-to-scrub, arrows, expressions or units | `number_field.dart:65-74` | Scrubbing, `1/3`, `2*pi`, `10cm` |
| Timeline: no zoom/scroll/frame snapping/multi-select; overflow on a 17-bone rig | `timeline_panel.dart:93, 253-260, 271-292`; `profile.frameSnap` is never read | Wheel zoom, a `ListView`, quantisation to `1/fps` |
| Weight paint without a brush cursor, without `[`/`]`, without Ctrl inversion | `weight_paint_panel.dart:156-170`; `view-21` deferred | A brush circle as an overlay — the minimum |
| The bone map is read-only | `bone_map_table.dart:6-11` | A dropdown per row (HumanIK/Rokoko) |
| Bevel and Extrude are one-shot with a guessed amount (10 %/5 % of the bounds) | `tool_commands.dart:48-50` | Interactive dragging after `E`/`Ctrl+B` |
| Only Euler XYZ, "Custom" in the auto-rig is a stub, the panel doesn't resize, RMB is unused | `transform_rows.dart:7-12`, `autorig_dialog.dart:372`, `shell.dart:158-170`, `modeler_viewport.dart:884-886` | A panel splitter, a context menu |

### 4.3 Hotkeys: action → Blender → Maya → here

| Action | Blender | Maya | Here |
|---|---|---|---|
| Move/Rotate/Scale | G/R/S | W/E/R | G/R/S (arm, then LMB-drag) |
| Axis in the modal | X/Y/Z, Shift+X | — | X/Y/Z, a second press = plane; only after the drag starts |
| Snap | Ctrl, Shift = precision | X/C/V | Ctrl; no precision |
| Orbit/pan/zoom | MMB / Shift+MMB / wheel | Alt+LMB/MMB/RMB | MMB / Shift+MMB / wheel; Alt isn't read |
| Orbit on a trackpad | two fingers | Alt+click | **none** |
| Object⇄Edit | Tab | F8 | **none** |
| Level v/e/f | 1/2/3 | F9/F10/F11 | 1/2/3 |
| Select all/none/invert | A / Alt+A / Ctrl+I | Ctrl+A | A (mesh only) / Alt+A / Ctrl+I |
| Loop/ring/linked | Alt+click / Ctrl+Alt / L | double click | **none** |
| Extrude / Loop cut / Bevel | E / Ctrl+R / Ctrl+B | Ctrl+E | E / C / B (one-shot) |
| Delete | X, Delete | Delete | X; Delete/Backspace **none** |
| Duplicate | Shift+D | Ctrl+D | D |
| Frame selected/all | . / Home | F / A | **none** (MCP only) |
| Undo/Redo | Ctrl+Z / Ctrl+Shift+Z | Ctrl+Z / Ctrl+Y | ⌘Z / ⇧⌘Z |
| Save | Ctrl+S | Ctrl+S | **none** |
| Insert key | I | S | I (pose), K (morphs) |
| Play/pause | Space | Alt+V | **none** |
| Brush radius | F / [ ] | B+drag | **none** |

### 4.4 Promised by the handoff vs implemented

| Screen | Present | Missing / different |
|---|---|---|
| 01 Object | list, 3×3 grid, stack (Mirror X), ⌀60 dial, axis colours, pivot/space chips | booleans on the rail; display chips in the viewport (they're in the panel); the dial is at the **bottom** right, not the top; the 3D cursor is disabled; Shift+RMB |
| 02 Mesh | selection level, card with a slider, n-gons in the status | perimeter/area summary, the modal readout, the axis line, snap chips, the diagnose/repair block |
| 05 Material | panel, graph, slots — **in Object mode** | the Material mode itself |
| 07 Animation | 270 timeline, transport, Keys/Curves, skeleton tree, constraints | zoom/scroll/snap, key multi-select |
| 13 Weights | gradient, legend, bend bar, brush, influences, bone list | brush cursor in the viewport |
| 14 Retarget | library, two viewports, tracks + blend, table, auto-map, root motion, lock feet | editable table; height-fit toggle |
| 15 Morphs | rows with a slider and a key dot, drivers, markers | live deformation; shape sets; per-shape key dot |
| 16 Auto-rig | modal, silhouette, humanoid/quadruped, options, summary | "Custom" |
| 24 Modifier stack | handle, reorder, one toggle | second toggle, fields per kind, warnings, counters, timing |

### 4.5 What to keep

- One tool table feeds the rail, the palette, the sheet, the keys and help
  (`tools.dart:1-9`, `shortcut_help.dart:32-40`).
- Escape rolls the modal back through a transaction, not an inverse matrix
  (`transform_session.dart:359-384`).
- The operation card = Blender's "Adjust Last Operation", done right.
- Box-select rules (shift adds / ctrl subtracts, subtract wins), a 4 px
  threshold for a mouse / 12 px for a finger (`selection_box.dart:38-102`).
- Ctrl snapping by displacement, not by position; geometric snapping that is
  byte-exact (`transform_gizmo.dart:426-430`, `geometry_snap.dart:76-81`).
- A fixed screen-size gizmo with hover highlighting
  (`transform_gizmo.dart:94-109`).
- `NumberField` accepts a comma and doesn't commit twice on Enter
  (`number_field.dart:1-13, 103-111`).

---

## 5. The "agent over MCP" lens

### 5.1 Critical

| Finding | Where | Recommendation |
|---|---|---|
| **Mesh element ids can't be read anywhere**, yet `select`/mesh commands require them: `list` gives only `id name (kind)`, `inspect` gives counters | `model_tools.dart:2326-2362`, `model_session.dart:94-109, 723-740`, `listing.dart:40-52` | `describe {id, level?, limit?}` with position/normal/area; `selectFacing {axis}`, `selectNear {point, radius}` |
| **`list` doesn't show transform, parent, material or `version`**; skeleton/clip/shape/modifier/light indices "from list" aren't listed (`skeletonsOf`/`clipsOf` → `const []`) | `model_session.dart:109`, `listing.dart:65-74` (the comment is stale: "phase 3") | Extend `list` and/or `describe` |
| **A type error = a mute refusal "cannot be read from those arguments"** with no field name; no JSON-schema validation — an unknown key is silently ignored (confirmed live: `select {ids}`) | `command.dart:503-506, 1435-1443`, `model_tools.dart:172-178`, `tool_table.dart:76-98` | Validate against `inputSchema`, name the field and the expected type |
| **One GPU upload failure wedges the session** (L4) | | |

### 5.2 Important

| Finding | Where | Recommendation |
|---|---|---|
| Hidden selection: `moveBy/…/extrude` read it, `addPrimitive` silently changes it, `separate` switches the mode, `cleanup`/`makeGameReady` overwrite it | `model_tools.dart:232-234, 461-465`, `object_commands.dart:115-118`, `mesh_commands.dart:714-718`, `model_session.dart:553, 624, 632` | An optional `ids`/`object` on every command; recipes restore the selection |
| Inconsistent vocabularies: `box` vs `cuboid`; `id`/`objectId`/`index`/`materialIndex`; `axis` as an int vs `"x"` | `object_commands.dart:67-73`, `model_tools.dart:424-433, 928, 1574, 1699, 1489` | One table of synonyms and addressing |
| Schema ↔ implementation: `bloomEnabled` isn't declared; `upAxis` is parsed as `== 'z'`; a typo in `render.view` silently gives `iso` | `model_tools.dart:2087-2089, 2550`, `lighting_commands.dart:292-295`, `render_tool.dart:36-42` | Generate enums from the same lists; refuse unknown values |
| Units and axes aren't named in `instructions` or most schemas (metres, Y-up, column-major, radians) | `model_server.dart:70-90`, `model_tools.dart:1597, 1678` | A paragraph in `instructions`, a unit in every description |
| `setMaterialField.value`: RGBA for `baseColor`, RGB for `emissive` — hidden in the description of the `field` field | `model_tools.dart:133-148` | A `oneOf` by `field`, or `setMaterialColor`/`setMaterialNumber` |
| An answer doesn't return the created id — only `says — selection`; after `duplicate/import/separate/buildFrom` a second `list` is needed | `model_session.dart:206, 712` | `structuredContent {did, says, ids, selection}` |
| Indices shift after `removeMaterial/removeJoint/deleteShape/removeLight` | `model_tools.dart:808-810, 1612, 1438-1440` | Stable ids like objects have, or an explicit warning in the answer |
| An agent's refusal isn't shown to the person in the status line; no "emergency stop"; "Undo agent steps" goes one step per click | `modeler_cubit.dart:52, 211-223`, `mcp_bootstrap_io.dart:82` | Refusal in the status line in `warn` tone; a "Pause agent" button; "Undo all agent steps" |
| One `StepAuthor.agent` for all clients; a person's `amend` keeps the agent as author | `history.dart:48, 408` | Author = client; `amend` changes the author |
| `instructions` don't mention `render`, `renderSheet`, `amend` or recipes; not a single MCP `prompt` | `model_server.dart:70-90` | `PromptsSupport` with `modelling_strategy`; `instructions` of 15–20 lines |
| `renderSheet` without quadrant labels, `render` without a size or element ids | `render_tool.dart:148-151` | `size`, labels, an "ids" mode |
| Dead-end schema fields (`bisect`, `flipUv`), "read the subtypes" references | `model_tools.dart:413-415, 949-951, 1048-1049` | `oneOf` by `kind` |
| `ui.*` take a `StringSchema`, not an enum | `mcp_ui_tools.dart:47, 96-98, 126-128` | enum |
| `addShape` duplicates `addShapeFromMesh`; 131 flat tools | `model_tools.dart:3095-3113` | Remove the duplicate; categories in descriptions |
| `save {}` in a GUI session always says "no path of its own"; sandbox refusals aren't described | `mcp_bootstrap_io.dart:64`, `model_session.dart:300-305` | Pass the open file's path; describe the sandbox |

### 5.3 Scenario "cube → extrude → GLB"

1. `addPrimitive {kind:"box"}` → "add a box — object 1" (the id only from the
   selection's tail).
2. `extrude {distance:0.2}` → "is still a cuboid. Convert it to a mesh
   first" — a good refusal, but not announced in advance.
3. `bakeToMesh {id:1}`.
4. `select {object:1, level:"face", elements:[?]}` — **guesswork**: face ids
   can't be obtained anywhere; the workaround is `selectAll` and extruding in
   every direction.
5. `extrude` → "faces 6, 7, …" — new ids without geometry.
6. `render {}` — a picture without element labels.
7. `check`, `export {to}` — on macOS in the GUI may fail on the sandbox with
   no hint in the schema.

At least 6–7 calls, two of them "blind".

### 5.4 Comparison with Blender MCP

The actual `blender-mcp` toolset (`src/blender_mcp/server.py`):
`get_scene_info`, `get_object_info`, `get_viewport_screenshot(max_size)`,
`execute_blender_code`, `describe_node_type`, `bpy_api_lookup`,
`export_scene`; integrations with PolyHaven, Sketchfab, Poly Pizza, Hyper3D
Rodin, Hunyuan3D; one `prompt asset_creation_strategy` ("first
`get_scene_info`, a screenshot before/after, source priority"). Transport — a
TCP socket without a token; the README warns "ALWAYS save your work".

| Capability | Blender MCP | flutter3d_model_mcp | Conclusion |
|---|---|---|---|
| Scene overview | `get_scene_info`: objects, types, positions, materials | `list`: id/name/kind; `inspect`: counters | adopt transform/parent/material/version |
| Object details | `get_object_info` | none | `describe` is needed |
| Screenshot | live viewport, `max_size` | headless CPU render, 7 views, 4 modes | we have determinism and multiple views; add `ui.screenshot` (what the person sees) and `size` |
| Editing | arbitrary Python | ~120 typed commands through `ModelHistory` | ours is safer and reversible; no escape hatch |
| Undo/authorship | none | `StepAuthor`, undo only one's own | ours is better |
| Transactions/batches | none | `buildFrom`, `cleanup`, `whenNotInTransaction` | ours is better; generalise to `batch {commands}` |
| Assets | PolyHaven/Sketchfab/PolyPizza/Rodin/Hunyuan | local `import` only | the main gap for indies: `importFromUrl`, HDRI → `setEnvironment` |
| API reference | `describe_node_type`, `bpy_api_lookup` | references to the sources | adopt for `TextureNode`/`ParametricShape`/modifiers |
| Export | `export_scene(selection_only, apply_modifiers)` | `export` + `check` + `force` | ours is better; add `selection_only` |
| Strategy prompt | `asset_creation_strategy` | no `prompts` | add |
| Security | socket without a token | loopback + token | ours is better |

**Is `execute_code` needed?** No: it breaks undo, the journal and authorship.
`batch {commands}` in one transaction plus low-level
`transformElements`/`setTransform` are enough; if necessary — sandboxed
expressions over `MeshData`, applied through `ApplyJobResult` with
`baseVersion`.

### 5.5 What to keep

A refusal as an answer (`answers.dart:17-28`, `history.dart:187-191`); one
source of truth for three surfaces (`model_tools.dart:161-186`,
`tools_test.dart:104-116`); authorship and one-way undo
(`model_session.dart:249-263`); locking for the duration of a person's
gesture (`history.dart:273-277`); stale-version protection and whole recipes
(`model_tools.dart:1205-1212`, `model_session.dart:657-685`); refusals with a
"where to go" hint (`mesh_commands.dart:55-56`,
`selection_commands.dart:476-477`, `model_session.dart:333-335, 823-830`);
loopback + a token per launch (`loopback_http.dart:22-32, 182-185`).

---

## 6. The "adaptivity and accessibility" lens

### 6.1 Critical

| Finding | Where | Recommendation |
|---|---|---|
| Orbit is unreachable with one finger and on a trackpad: a one-finger drag is always a box (`onBox` is always set), two fingers pan/zoom | `modeler_viewport.dart:773-807`, `ready_parts.dart:388`, `orbit_gestures.dart:375-410` | One finger = orbit unless a drag tool is armed; box on long-press |
| "Animation" on the tablet is an empty screen: `animationSubmode`, `bottom` and `agentPanel` go to the desktop only; the tablet palette calls `toolsFor(mode)` without `animation:` → empty. On the phone, with `mode == animation` "Object" is highlighted | `shell_for_width.dart:50-76`, `shell_tablet.dart:158`, `tools.dart:385-386`, `shell_phone.dart:164-166` | Pass them into the tablet shell; on the phone — reset the mode when the shell changes |
| Fixed-size modal dialogs (900×720, 980×720, 720×520) don't fit a tablet/phone; the only test is 1400×900 | `lathe_dialog.dart:150-152`, `autorig_dialog.dart:230-232`, `material_studio_dialog.dart:291-293`, `lathe_dialog_test.dart:73` | `LayoutBuilder` → `Dialog.fullscreen` below 1200 |

### 6.2 Important

| Finding | Where | Recommendation |
|---|---|---|
| The tablet top bar: 12 actions don't shrink, modes go into a scroll | `shell_tablet.dart:70-82`, `top_bar_actions.dart:85-210` | An overflow like the phone's |
| No document name or unsaved marker on tablet/phone | `shell_for_width.dart:60-65` | `documentName`/`isDirty` in the header |
| The sheet handle doesn't drag, the sheet can't be dismissed; 200/130 px cover the viewport | `shell_tablet.dart:220-260`, `shell_phone.dart:142-150` | `DraggableScrollableSheet` with snap points |
| The sheet starts with Display/View (~130–150 px) — on the phone only "DISPLAY" is visible | `properties_panel.dart:428-481` | On touch — chips over the viewport, the sheet starts with the mode's content |
| The FAB has no accessible name | `shell_phone.dart:153-160` | `tooltip: armed.label` |
| The `ui-23` pattern isn't applied everywhere: `skeleton_tree.dart:140-146`, `constraints_list.dart:74-77`, `morphs_panel.dart:223-229, 305-309`, `texture_graph_panel.dart:206-212`, `scene_source_panel.dart:98-102`; `accessibility_test` checks shells with empty `properties` | | The same wrapper; `labeledTapTargetGuideline` over a real panel |
| Tap targets of 14–22 px inside panels on touch; `InputPolicy.touchTapTarget` is read only by a test | `texture_graph_panel.dart:208`, `operation_card.dart:126-127`, `morphs_panel.dart:307`, `theme.dart:339`, `input_policy.dart:97` | `visualDensity`/`iconButtonTheme` 48 when `LayoutClass != desktop` |
| Text scale checked only at 1.3× on an empty shell; fixed heights of 32/30/52 | `accessibility_test.dart:64-99` | A 2.0× test with a real panel; `TextScaler.clamp` for chrome |
| Keyboard navigation isn't designed: one `Focus(autofocus)`, the viewport is a `Listener` | `modeler_keys.dart:96-97` | A `FocusTraversalGroup` per region; arrows for orbit |
| Help on the tablet has no gestures | `shortcut_help_screen.dart:41-75` | A "Touch and pen" section from the `OrbitGestures`/`InputPolicy` rules |
| Surface tones and the selection colour differ from the handoff: status `surfaceContainer` vs `Low`; panel `Low` vs `Container`; background `#14181A` vs `#0B0E0F`; selection `#FF9926` vs `#004F58` 55 % + `primary` | `shell.dart:166, 188`, `theme.dart:150, 250, 283` | Align, or fix them in `theme_test` as deliberate |

### 6.3 Contrast (WCAG)

| Pair | Ratio | Verdict |
|---|---|---|
| onSurfaceVariant `#BFC8CA` / surfaceContainer `#171A1B` | 10.27:1 | AAA |
| outline `#899295` / surfaceContainerLow `#131617` (11 px labels) | 5.72:1 | AA |
| primary `#5FD4E4` / viewport `#0E1112` | 10.86:1 | AAA |
| onTertiaryContainer `#FFD9B0` / `#3A2118` | 11.20:1 | AAA |
| tertiary `#FFB86B` (warn) / surfaceContainer | 10.27:1 | AAA |
| error `#FF5449` (refuse) / surfaceContainer | 5.51:1 | AA |
| secondary `#FF458E` / viewport | 5.86:1 | AA |
| label `#0E1112` / X+ ball `#C2566E` (9 px) | 4.38:1 | below AA for small text |
| outlineVariant `#3F484A` / surfaceContainerLow (sheet handle, tracks) | 1.94:1 | **FAIL** for UI elements (3:1) |

### 6.4 Localisation

- `app_en.arb` ≈ 67 keys; `lib/src/ui/` has ≈ 190 hard-coded strings
  (113 `Text('…')`, 17 `tooltip:`, ~60 labels in `tools.dart`). The share of
  unlocalised visible text is **~75 %**.
- The `sectionDisplay…viewBottom` keys exist in `arb`, but
  `properties_panel.dart` doesn't read them.
- The "Scene" panel is the only Russian one, which is why one screen speaks two
  languages (L10).
- The handoff's font (Roboto) isn't set (`theme.dart:293-325`).

Recommendation: close `ui-22` entirely, and don't declare `ru` until then; a
test that fails on `Text('` outside an allow-list.

### 6.5 Feature → desktop / tablet / phone

| Feature | Desktop | Tablet | Phone |
|---|---|---|---|
| Camera orbit | mouse: MMB only; trackpad — **no** | **no** | **no** |
| Object/Mesh/Material/Scene | yes | yes | yes |
| Animation | yes | **empty screen** | **no** |
| Timeline / bend bar / retarget | yes | no | no |
| Agent Session | yes | no | no |
| Properties panel | 250–330 at the side | 200 sheet, doesn't collapse | 130 sheet, doesn't collapse |
| Document name, "•" | yes | no | no |
| Lathe / Auto-rig / Material Studio | yes | overflow | unusable |
| Export / Import / Start | yes | yes | yes, with scrolling |
| Help "?" | keys | no gestures | no gestures |

### 6.6 What to keep

The pen never orbits the camera, pressure and the inverted tip are handled
(`input_policy.dart:108-123`); one tool table for three shells, with a test
that actually presses every tool (`shell_layout_test.dart:122-210`); undo/redo
say what they will undo, for a screen reader too; semantics for number fields
and sliders (`transform_rows.dart:113`, `operation_card.dart:221-223`); phone
bugs found by review are closed by tests (`shell_layout_test.dart:286-360`).

---

## 7. Is a "simple / professional" mode needed?

**A global switch — no.** Industry experience: Blender 2.5 removed such a
mode; SketchUp and Fusion keep it as "workspaces", not "levels". A global mode
doubles the test matrix, hides features a beginner will never learn about, and
doesn't solve the main problems above (input, reliability, state for the
agent) — they are the same for everyone.

What instead, in decreasing order of payoff:

1. **Keymap presets** (Blender / Maya / own), as in Godot and Unity: removes
   the §4.3 conflict without losing our own keymap.
2. **Progressive disclosure inside panels**: the material graph collapsed
   (already a handoff §05 principle), modifier fields expanding on click,
   "Advanced" on import/export. The first level is what "scan → GLB" needs.
3. **Workspaces in the mode switcher**: "Essential" (Object, Material, Scene)
   and "Full" (+ Mesh, Animation); modes that aren't ready aren't shown at all.
   On touch shells — "Essential" by default. This is the form of "switching
   modes" that looks sensible: the set of screens changes, not the behaviour of
   the tools.
4. **A guided start**: the start screen on first launch, four scenario cards
   (a scan, primitives, a character, a scene), an orbit hint in the viewport
   corner.

---

## 8. Good practices — combined

The same seven things recur across the four lenses, and they are the backbone
that must not be lost in any rework:

1. A command as a value: `says`, JSON arguments, `hints` — one table for the
   status line, the card, the keys and MCP.
2. `amend` instead of growing the undo stack when adjusting the last operation.
3. A refusal is an offer, not an exception; a refusal doesn't touch the stack.
4. Step authorship and the agent's one-way undo, visible in the panel.
5. Readiness in three tones, in words that name consequences, with a jump to
   the object.
6. A file that can't be read never replaces the document; recovery names the
   number of objects.
7. One input classifier (`InputPolicy`, `OrbitGestures`) with no Flutter in
   it, tested as pure functions.

---

## 9. Documentation vs code

| Document | Claim | Actually |
|---|---|---|
| `docs/modeller.md` §14 | `import {path/bytes, …}` | only `from` (a path); no `bytes` (`model_tools.dart:2512-2538`) |
| `docs/modeller.md` §4 | `ui.openDialog` opens export/lathe/autorig/preview | autorig and preview answer "not built in this app yet" |
| `docs/modeller.md` §2 | selection goes through the `SelectElements` command | true for `ModelSession`/MCP; a person's clicks write `history.selection` directly (`interactions.dart:36-48`, `ready_parts.dart:168-178`) — the recovery journal after a mouse click diverges from the document |
| `docs/modeller.md` §12 | 8 light sources at most | the panel shows "0 of 6 shadowed" — the difference between the shadow limit and the light limit is worth naming |
| `listing.dart:65-74` | "phase 3, ModelProject has nowhere to keep one yet" | the project does have skeletons and clips |
| `files.dart:872-880` | a reference to a "concurrent uncommitted `_openFile` refactor" | it isn't in the tree; this is why the bypass of the import screen lives on |
| `01-prop-from-a-scan.md` step 1 | "The start screen offers Open file, New project…" | the app starts with a cube; the start screen is a dialog behind ⌂ |

---

## 10. Backlog by priority

The `ux-NN` numbering is a proposal for `doc/model-editor-plan.md`.

### P0 — blockers of trust and the first hour

| ID | What | Finding |
|---|---|---|
| ux-01 | Autosave: create the directory, an honest status, an honest crash dialog | L1 |
| ux-02 | `SceneSync.apply` doesn't take the session down over one object; MCP doesn't return stacks | L4 |
| ux-03 | The gizmo over geometry and a working mouse drag, with an event-stream test | L3 |
| ux-04 | Orbit: Alt+LMB, two fingers, one finger on touch | §4.1, §6.1 |
| ux-05 | The agent panel and the contact sheet — on actual connection, collapsible | L5 |
| ux-06 | The start screen and "Recent" through the import screen; defaults STL → mm, weld on | §3.2 |
| ux-07 | "Material" mode: the materials section there, or `ready: false`; unready modes unreachable through `ui.setMode` too | L6, L9 |
| ux-08 | The debug `ListTile`/`ColoredBox` assert; `CrashDialog` deduplication | L2 |

### P1 — regular irritation

| ID | What |
|---|---|
| ux-10 | ⌘S, Delete/Backspace, Tab, `.`/Home frame, Space play; keymap presets |
| ux-11 | Modal readout, axis line, angular rotation, Shift precision, snap chips |
| ux-12 | Pivot/Space apply to interactive transforms |
| ux-13 | Modifier stack: kind picker, fields per kind, second toggle |
| ux-14 | Outliner: hierarchy, visibility, multi-select, rename |
| ux-15 | Number fields: scrubbing, arrows, expressions, units, adaptive precision |
| ux-16 | Diagnose and repair in the Mesh panel; "Build topology" for imports |
| ux-17 | Refusals in `warn` tone, full text in a tooltip, multi-line ones in a snackbar |
| ux-18 | One export dialog; formats from `builtInModelWriters`; hints for terms |
| ux-19 | MCP: `describe`, `list` with transform/material/version, `structuredContent` with ids, schema validation, units in `instructions`, `prompts` |
| ux-20 | MCP: an optional explicit target on commands instead of hidden selection; `batch` |
| ux-21 | Tablet: animation, fullscreen dialogs, top-bar overflow, document name, draggable sheet |
| ux-22 | Localisation to the end; one language per panel; pluralisation |
| ux-23 | "Scene": field labels above the field, lights above the scene |
| ux-24 | Live morph deformation in the viewport; weight brush cursor |

### P2 — rough edges

| ID | What |
|---|---|
| ux-30 | The "opened in N ms" chip is temporary; window title = document; Save filled when `isDirty` |
| ux-31 | The Add menu with labels and icons; "Wire" by `EditMesh` edges |
| ux-32 | Surface tones and selection colour per the handoff, or a recorded deviation; Roboto |
| ux-33 | `ui-23` in the remaining five files; FAB tooltip; 48 targets on touch; a 2.0× test |
| ux-34 | Sheet handle/track contrast ≥ 3:1; orientation dial labels |
| ux-35 | Remove the `addShape` duplicate; enums in `ui.*`; `bloomEnabled` in the schema; `render.size` |
| ux-36 | Documentation: §14 `import`, §4 `ui.openDialog`, §2 selection in the GUI, `listing.dart`/`files.dart` comments |
| ux-37 | "Essential/Full" workspaces and a guided start (§7) |
