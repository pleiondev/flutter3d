---
title: A prop from a scan
summary: An STL from a 3D scanner, in millimetres, cleaned, painted and exported as a GLB you can drop into a scene.
---

# A prop from a scan

**What you have:** a single STL file off a 3D scanner or a CAD export —
`teapot.stl` in this walkthrough, the classic scanned-object stand-in every
3D tool ships with. **What you want:** a GLB, at the right real-world scale,
with one clean material, ready for a game engine or another scene.

This case exercises the start screen, the import dialog's own unit and
axis choice, the export panel's own checks, and the material panel in
between — the same four screens (20, 21, 05, 22 in the design handoff) that
every "bring in somebody else's object" job in the modeler touches.

## 1. Start

Launch the modeler. The start screen offers **Open file**, **New project**
and a list of anything you opened recently. Choose **Open file** and pick
`teapot.stl`.

*(screenshot: the start screen — placeholder, see note at the end of this
page)*

## 2. Import: units and axis

STL carries no unit at all — a scanner or a CAD tool that wrote "3.15" meant
something by it, and the file does not say what. The import screen asks:

- **Unit** — millimetres, centimetres or metres. This scan is millimetres,
  the STL default this project's own import options assume
  (`ImportOptions.scale = 0.001` reads a millimetre file as this project's
  metres).
- **Up axis** — Y (this project's own convention) or Z (common out of CAD
  tools). This file is already Y-up, so the default is correct.
- Three checkboxes: **weld** coincident vertices, **fix normals**,
  **triangulate**. Leave weld on — an STL is a flat triangle soup with no
  shared vertices at all until something welds them, and turning it into
  real topology is what lets the editor's other mesh tools (**Clean up**, a
  later edit) act on the object at all — not, any more, what lets it be
  diagnosed; see the note below. Fix normals and triangulate are not needed
  here.

Choosing "mm" here is exactly `ImportUnit.millimetres` in
`apps/flutter3d_modeler/lib/src/import_plan.dart`; the bounds preview the
real screen shows is `ImportPlan.scaledBounds` reading the file's own
`computeBounds()` through that unit.

*(screenshot: the import dialog with "mm" chosen and the bounds preview —
placeholder)*

> **Diagnosis does not wait for weld.** `ExportReadiness` used to run its
> mesh checks (degenerate faces, pinched vertices, inside-out shells) only
> against a mesh that already had real topology — an `EditedGeometry`
> object — so a file straight off the STL loader, still `ImportedGeometry`,
> read "ready to export" no matter what was actually wrong with it. That was
> a real gap (`tut-01` in `doc/modeler-tutorial-gaps.md`), closed since: the
> same three checks now run against a throwaway mesh built from the
> imported buffer purely to ask them, so the status line reports this
> teapot's pinched vertex whether or not "weld" is ticked. Leave weld on
> anyway — it is what turns the file into a mesh the editor's other tools
> can act on, which diagnosis alone was never going to give you.

## 3. Diagnose

The status line's readiness segment says what it finds as soon as the file
is imported — welded or not, now that `ExportReadiness` reads an imported
mesh's own topology too. For this file, once it is welded and renamed
"teapot":

```
exports with a warning: "teapot" has 1 vertex where two pieces of surface
meet at a point and are joined nowhere else; the shading there will be wrong
and nothing downstream can thicken or subdivide it
```

That is `ExportReadiness.says` (`packages/flutter3d_model_core/lib/src/
readiness.dart`) reading the one non-manifold vertex `MeshChecks` finds in
the welded teapot — the point where the lid and the body's topology meet.
Running **Clean up** (the same "weld duplicate vertices, drop degenerate
faces, fix winding" recipe `session.cleanup()` runs as one undo step) does
not change this: there is nothing left for it to weld or drop, and there is
no command in this build that un-pinches a single vertex two shells share.
The warning stays. It is a warning rather than an error because nothing
about the desktop export profile requires a fully manifold mesh
(`ProjectProfile.requireManifold` defaults to `false`) — the file will load
and draw correctly everywhere that matters for this job, so this is the
right moment to accept it and move on rather than chase a fix that does not
exist yet.

## 4. Material

Open the material panel and add one material: **glazed ceramic**. Set:

- **Base colour** — a warm off-white, `(0.92, 0.89, 0.82)`.
- **Metallic** — `0`.
- **Roughness** — `0.28` — glossy enough to read as a glaze, not a mirror.

Assign it to the teapot. The material list shows one row with a colour
swatch instead of a checkbox, and the status line's material count moves
from 0 to 1.

*(screenshot: the material panel with "glazed ceramic" set and assigned —
placeholder)*

Below are the same teapot rendered twice, headlessly, through
`renderProject` (`packages/flutter3d_model_mcp/lib/src/render_tool.dart`'s
own underlying function) — no viewport chrome, just the geometry, the way
`render`/`renderSheet` would hand it to an agent:

![The teapot as it lands from the STL loader, before any material — the loader's own default grey](/assets/learn/modeler/prop-from-a-scan/05-imported-raw.png)

![The teapot with "glazed ceramic" assigned](/assets/learn/modeler/prop-from-a-scan/06-final-material.png)

These two are real renders of this exact case's own project data (see
"Proving it" below) — not mockups. They are rendered at 20× the model's
real size for legibility; see the note at the end of this page for why.

## 5. Export, with checks

Export to GLB. The export panel shows the same readiness sentence as the
status line and, because nothing here is an error, writes the file with the
warning noted rather than refusing:

```
written to teapot.glb, with 1 warning: "teapot" has 1 vertex where two
pieces of surface meet at a point and are joined nowhere else; the shading
there will be wrong and nothing downstream can thicken or subdivide it
```

That is `ModelSession.export`'s own answer sentence
(`packages/flutter3d_model_mcp/lib/src/model_session.dart`), verbatim.

*(screenshot: the export dialog, readiness warning and all — placeholder)*

## 6. Into the cabinet

Sign in at models.pleion.dev and upload `teapot.glb` from the site's own
uploader. It joins your cabinet with the name you exported it under, and
"Open in viewer" loads it at `/app/` — the same web build of the modeler
this whole case ran in, reading the file back rather than a special
viewer-only path. Two things the cabinet cannot do yet, so you are not
missing a setting: it has no preview picture of its own (`cloud/README.md`'s
own "What is not here yet"), and there is no way to open a cabinet model
back into the desktop editor and save changes to it — export is presently
one-way.

---

## Notes on this page

**Time to complete:** not recorded yet. `TODO`: a person should walk this
case by hand on a real machine and fill in a line here — "*n* minutes,
*date*, *machine*" — the way `rel-09`'s own cohort rows do. Nothing in this
session could actually run the desktop app, so no time is claimed.

**Screenshots.** Four pictures on this page are placeholders — a plain
colour with "screenshot pending" on it, at
`cloud/server/web/assets/learn/modeler/prop-from-a-scan/{01-start-screen,
02-import-dialog,03-material-panel,04-export-dialog}.png` — standing in for
the modeler's own running UI (start screen, import dialog, material panel,
export dialog). The two teapot renders above are real: real STL decode,
real import options, real material commands, run against a real
`ModelSession`, rendered by the same CPU renderer `render`/`renderSheet`
use. What is missing is the *chrome around* the 3D content — the panels,
buttons and dialogs a person actually clicks — because this page was
written in a sandbox that cannot open a macOS window
(`flutter run -d macos` fails to foreground here, the same limit
`tool/tutorial/shoot.dart`'s own screencapture path already documents).

To replace the four placeholders on a real Mac:

1. `cd apps/flutter3d_modeler && FLUTTER3D_WINDOW=1440x900 flutter run -d macos --dart-define=mcpPort=0`
2. `dart run tool/tutorial/bin/shoot.dart` against a scenario that: opens
   the start screen (`01-start-screen`); opens `teapot.stl` and shows the
   import dialog with "mm" chosen (`02-import-dialog`); adds and assigns
   "glazed ceramic" and shows the material panel (`03-material-panel`);
   opens the export dialog on `teapot.glb` with the warning showing
   (`04-export-dialog`).
3. Copy the four PNGs over the placeholders at the paths above and remove
   this note once they are real.

**The render scale.** The two real renders are of the imported project
scaled up 20× for the picture only (`tool/make_case1_fixtures.dart`'s own
`_scaledForRender`) — the exported `case1.glb`/`case1.f3dproj` fixtures are
never scaled this way, only the pixels above. This works around a real gap,
`tut-02` in `doc/modeler-tutorial-gaps.md`: `renderProject`'s own camera fit
floors its bounding radius at 5 cm, so an honestly millimetre-scale prop —
this one is about 8 mm across — renders as a few pixels in the middle of
the frame instead of filling it. The interactive viewport's own camera fit
has no such floor and would show the same object large and clear, so this
is a headless-render-tool limitation, not something you would see using the
real app.

**Proving it.** Every step above is a real, replayable command, not
narration. `packages/flutter3d_model_mcp/test/fixtures/tutorial/
case1_scenario.dart` builds exactly the project this page describes,
through `ModelSession.import` itself — the same call an agent makes over
MCP, given `ImportOptions(scale: 0.001)` and `weld: true` for the identical
"mm" and "weld coincident vertices" choice made above;
`packages/flutter3d_model_mcp/test/tutorial_scenarios_test.dart` replays
its journal (`case1.jsonl`) through `CommandJournal.replay` against a
freshly imported teapot and checks the result matches the committed
`case1.f3dproj` and `case1.glb` byte for byte, plus a
`compareModelDocuments` check on the exported GLB read back. The one thing
the journal does not carry is the import step itself: `ReplaceDocument` —
what an import runs — is deliberately not journalable (`command.dart`'s own
doc comment, `flutter3d_model_core`), so replay starts from the project
right after import rather than from an empty one.
