# Lesson scenarios — the content development plan

Written 2026-09-12, on top of [doc/tooling-plan.md](tooling-plan.md) (the
owner's own 2026-09-11 decisions, §3 of that plan) and the same day's
decisions: this document plans **scenarios**, not tools. One interactive
format — `edu-00` in tooling-plan.md: steps, layer-by-layer disassembly,
annotation widgets, cross-sections, property-to-data bindings, a checked
question — serves four different uses, and tooling-plan.md builds the format
and its authoring (`edu-00`/`01`), widgets on surfaces (`wg-00`/`01`/`02`) and
non-game templates (`tpl-04`). This plan lists what concrete content gets
built on that foundation: which teardown, which device, which lesson — across
the four segments the owner's own request named: games, education, industry,
VR/XR.

**Nothing here starts before its own dependency.** Every scenario names the
tooling-plan.md item it cannot be assembled without, and most scenarios wait
on `wg-01` and `edu-01` — both L, both on track B's critical path
(tooling-plan.md §5). What can be done right now is subject-matter work, not
code: choosing a real device for a digital twin, a real drawing to disassemble,
text for the steps — and that is the plan's first part.

Notation — as in tooling-plan.md: **size** — how big for one person (S up to
a week, M two to three, L a month or more); **⇢ X** — the scenario absorbs
item X's own acceptance from tooling-plan.md rather than duplicating it. Id
prefixes: `ls-g` games, `ls-e` education, `ls-i` industry, `ls-x` VR/XR.

---

## 1. In short

1. **One document, four storefronts.** `edu-00` does not know who is looking
   at it — a schoolchild, a plant engineer, or a buyer in VR. Hence the
   decision: not four content formats, but four collections of scenarios on
   one format, and the first scenario actually built (`ls-e-00`, an engine
   teardown) is literally `edu-01`'s own acceptance from tooling-plan.md, not
   something layered on top of it.
2. **Subject-matter work does not wait on code.** Choosing a real object
   (which engine, which device for a digital twin, which plant component),
   writing the steps' text and the check questions — all of it can be
   prepared while `wg-01`/`edu-01` are being written. §2 is what to do right
   now.
3. **Games get the interactive twice: outside and inside.** Outside — the
   site's own guides (`site/content/*/tutorial.md`) grow an embedded live
   scene through the `tpl-02` gallery. Inside — a teaching moment inside the
   game itself through `WidgetSurface` (`wg-01`, demo `wg-02`), which none of
   the four demos have today: a player learns a rule from a pop-up hint
   in the world, not from text on a website.
4. **Industry and VR/XR are the same scenario, viewed two ways.** A device
   twin (`ls-i-00`) through `StereoViewer` (`flutter3d_stereo`) is `ls-x-03`:
   the same device tree and the same broker binding, a different viewport.
   Duplicating the content is not the plan — a display parameter is.
5. **The content critical path is not the code critical path.** `wg-01` and
   `edu-01` (both L) sit on tooling-plan.md's own critical path; scenarios
   that depend only on `edu-00` (the spec, S, no engine change) can be built
   earlier — they wait on the document, not on the authoring tool.

---

## 2. What can be done before the code is ready

Subject-matter preparation, no building: pick the object, write the steps,
code nothing. All four are groundwork for the scenarios in §3–§6.

| id | What | size | for scenarios |
|---|---|---|---|
| prep-00 | Pick a real assembly to disassemble (an engine or a similar mechanism with 5–8 natural steps, available as a model or a geometry reference) | S | ls-e-00, ls-x-00 |
| prep-01 | Pick a real device for a digital twin: what it measures, where the data comes from (an MQTT/WebSocket broker, real or a sampler), which 3–4 properties are worth showing | S | ls-i-00, ls-x-03 |
| prep-02 | Write the text and questions for three teaching scenarios (physics — a pendulum, geometry, a subject of the testing instructor's own choosing) with a checkable answer per step | S | ls-e-01, ls-e-03 |
| prep-03 | Pick which of the existing `site/content/*/tutorial.md` guides get an embedded live scene first — candidates: `platformer/tutorial.md` (already five steps of text), `racing/tutorial.md` | S | ls-g-00 |

---

## 3. Games (`ls-g-`)

| id | Scenario | Format (from `edu-00`) | Depends on | size | Acceptance |
|---|---|---|---|---|---|
| ls-g-00 | **A platformer level teardown in the guide.** `platformer/tutorial.md` gets an embedded live scene: steps highlight the spring, the door and the key on a real, playable level (`ascent.json`), not a screenshot | steps, annotations | tpl-02, edu-00 | S | the site's guide shows a live scene, the "door" step highlights `the blue gate`, an "open in the web editor" button leads to the same level |
| ls-g-01 ⚠ | **The dungeon's first five minutes teach the rules through play, not text.** The first monster encounter shows a pop-up hint panel through `WidgetSurface` — not a pause, not a text screen, but a widget on a surface in the world (⇢ demo `wg-02`, "a terminal with an event log," grown into a full teaching moment). Built 2026-09-14: `firstShotHintFor` (`apps/flutter3d_demo_dungeon/lib/src/first_shot_hint.dart`) says one sentence — "The doorway gives you room to aim before it reaches you," the guard room's own design note from `make_crypt.py` turned into something a first-time player is told — the first time a run's own events carry a `ShotFired`, through the same `wg-02` `run-terminal` `WidgetSurface` already proven on this level, and stays quiet for the rest of that run; a restart (`_beginDemo` resets the flag) teaches it again. **The trigger is a real, named substitution, not "the first monster encounter" literally**: nothing in this engine reports a monster noticing or being noticed, so "the first shot fired" stands in for it — close for a level whose own first room gives the player the shot before the runner can close the distance, but not the same event were a level ever built where the two diverge. The acceptance itself is unverifiable by anything in this session, exactly as its own text says — "manual A/B, not automated" — so what is checked instead is that the mechanism fires correctly: `first_shot_hint_test.dart`, four tests, a pure function taking events and a flag with no simulation behind it | annotation widget | wg-01, wg-02 | S | a new player clears the first room without outside instruction more often than without the hint (manual A/B, not automated) |
| ls-g-02 | **The racing garage as an interactive.** The car-setup screen between races gets "tyres → suspension → gear ratio" steps, each annotated with what it changes on the track | steps, property bindings | edu-00, wg-01 | S | a player goes through the garage once before their first race, each step highlights the part of the car it changes |
| ls-g-03 | **The strategy game's first ten minutes as an interactive briefing.** Building order, fog of war, the unit triangle — steps over the real match map, not a separate cutscene | steps, annotations | edu-00 | S | the briefing plays out on the demo match's own map, each step shows what it is talking about rather than text on a black screen |
| ls-g-04 | **Shooter secret-hunting — a level cross-section.** A wall cross-section shows a hidden room in full, a step names which lever opens it | cross-section, steps | edu-00, wg-01 | S | a player using the interactive finds every secret in the level faster than from a text guide (measured on a pair of playtesters) |

---

## 4. Education (`ls-e-`)

| id | Scenario | Format | Depends on | size | Acceptance |
|---|---|---|---|---|---|
| ls-e-00 ⚠ | **An engine teardown in five steps.** ⇢ `edu-01`'s own acceptance from tooling-plan.md — not separate work, but the first real content built on the authoring tool: an instructor assembles a teardown in the browser with no code and gets a link. Played through half of it: `apps/flutter3d_lesson_viewer/assets/levels/teardown.json` is a real five-step walkthrough (block → valve cover removed → filter removed → spark plug removed → block remains), four named parts, `visible`/`hidden` genuinely hide and show nodes; a real gap was found and closed along the way — `LessonCubit.open` built a `LessonPlayer` but never built or passed the "entity name → node" map, so `visible`/`hidden` never worked anywhere in this app before that fix. The level was written by hand, not assembled through `StepPanel` in the browser — but that does not mean the editor could not: it does not have to know about `'part'` in advance at all (`paletteOf` is built from the document, `Editing.place` copies the size/material of the last entity of that kind), and `packages/flutter3d_editor_core/test/palette_test.dart`'s new `ls-e-00` group opens this same `teardown.json`-shaped document and places a second part with the right size and material, with not one edit to the editor. `lesson_authoring_test.dart` (already existing) goes further and assembles the whole five-step lesson — steps, an annotation, a cross-section, AND `offsets` — through `Place`/`SetField`/`Turn`, but `offsets` in that test is arithmetic for a hypothetical scenario (one named node inside a single model) this very file does not use: `teardown.json` disassembles four SEPARATE entities, each with its own `EntityDef.position`, and the ordinary `AxisDrag`/`MoveBy` already moves them today — no node-level drag and no `mergedOffsets` involved at all. Owner decision 2026-09-13, after checking: the node-level drag stays unwired deliberately, not as a gap — building it for a data shape this lesson never chose would be work with no scenario behind it | steps, layer-by-layer disassembly, annotations | edu-01, prep-00 | S | a link opens for a second person with no explanation needed; the five steps play in order, each names its part |
| ls-e-01 ⚠ | **A virtual lab — a pendulum.** ⇢ `edu-04`'s own acceptance: a student changes the string length through a `WidgetSurface` parameter panel, the result reproduces on a weak laptop, an instructor opens the student's own run in `rp-02` | data panel, property binding, a run | edu-04, rp-02, prep-02 | S | an instructor sees on rp-02's own timeline which step the student set a length different from the assignment. Closed 2026-09-14 against this row's own literal question, "which step" — not against "on rp-02's own timeline," a screen that does not exist: `rp-02`'s own status note already named this exact gap ("an instructor scrubs a student's own run in `rp-02`'s timeline is a UI opening this session doesn't have"), unchanged here. `PendulumLabRun.divergenceFrom` (`flutter3d_lab`) compares a student's own `checkpoints` (`DigestTrace`, `rp-01`'s mechanism) against an assignment's, and on the first checkpoint that disagrees, reads both runs' own `lengths` (`DataSourceTrace`, `edu-05`'s mechanism) at that exact step — not just "the state diverged," but the two numbers that explain why. Two new tests: a student who changed the length is caught at the very first checkpoint, with both lengths named correctly; two runs of the same length report no divergence at all. `apps/flutter3d_lab_pendulum` (the app `edu-04` already ships) is untouched — this is the same "prove the mechanism, draw the panel later" split `wg-00`/`rp-02` themselves already used |
| ls-e-02 ⚠ | **A checked lesson: cell structure, or a similar subject the biology/anatomy team chooses** — a second subject vertical after engineering, layers and annotations instead of a mechanism teardown, with a question at every step | steps, layers, a checked question | edu-01, prep-02 | S | a student clears the lesson within three attempts at the question, the result is visible to the instructor through `edu-03`. Closed 2026-09-14 against the half of this acceptance that is not `edu-03`'s own — LTI/xAPI is explicitly out of scope for the standing goal this row serves. `apps/flutter3d_lesson_viewer/assets/levels/cell.json`: four steps peel back a cell's own layers (membrane → cytoplasm → the organelles it left exposed) using the same `part`/`visible`/`hidden` mechanism `ls-e-00`'s teardown already proved — "layers" read as this rather than as `offsets` (§6 of `edu-00-interactive-format.md`), which needs a real named-node model and an interpolation host neither of which exists anywhere in this tree yet, the same gap `ls-e-00`'s own status note already named. Every step carries a real `check` — a question, several accepted phrasings, three attempts — the exact mechanism `check_prompt_test.dart` already proved, exercised here against real content for the first time (`cell_test.dart`, five tests: order, starting visibility, the peel sequence, every step naming a gradeable question, and a correctly-graded answer). No new code, the same as `ls-i-03` |
| ls-e-03 | **The same lesson inside an LMS.** `ls-e-00` or `ls-e-01` launches from a test Moodle through LTI, the step question's answers go to the course log as xAPI | LTI/xAPI (⇢ `edu-03`) | edu-02, edu-03 | S | the grade for `ls-e-02`'s own question is visible in the test Moodle's log |
| ls-e-04 | **Corporate safety training.** A real equipment teardown (content shared with `ls-i-03`) with "danger" annotations on a step, embedded in a corporate portal through `edu-02`'s own embed | steps, annotations, embed | edu-01, edu-02 | S | the interactive embeds into a test internal page through an iframe with no code. The shared content half exists now — `ls-i-03`'s own `housing.json` — but the "danger" annotations and the `edu-02` iframe embed are not built here |

---

## 5. Industry (`ls-i-`)

| id | Scenario | Format | Depends on | size | Acceptance |
|---|---|---|---|---|---|
| ls-i-00 ⚠ | **A device twin with "what if."** ⇢ `edu-05`'s own acceptance: a machine from the `tpl-04` template shows temperature from a broker (real or a sampler), "what if" branches from the current step with a substituted value | data binding, branching | edu-05, tpl-04, prep-01 | M | the temperature on the panel follows the source; changing the value creates a visible branch rather than overwriting history. Closed 2026-09-14 at the mechanism level, both halves. "Follows the source": `apps/flutter3d_template_app`'s own live loop already resolves `twin.json`'s `bindings` every frame through `flutter3d_twin`'s `spindleTempAt` — proven by that app's own `tpl04_levels_test.dart` plus `flutter3d_twin`'s own tests against the real production formula, not only a synthetic one. "A visible branch, not an overwrite": `SpindleTempRun.branchAt` (`flutter3d_twin`), built directly on `DataSourceTrace.branchAt` (`flutter3d_sim`) — the same primitive `flutter3d_lab`'s own `PendulumLabRun.branchAt` already proved for `edu-04`, applied here for the first time to a pure data-source twin with no physics behind it. Four tests: an unbranched run reads the real formula throughout; branching leaves the original run's own trace untouched; a branch agrees with its source up to and including the branch step, then reads the substituted value from the next step on; a branch can itself be branched again without disturbing either earlier one. **Not built**: any UI — no panel exists anywhere for typing a "what if" value, and `apps/flutter3d_template_app`'s own live loop is a plain per-frame ticker, not built on `flutter3d_sim`'s deterministic `GameSimulation`, so wiring this mechanism into that app's actual running scene is real, separate work this row does not attempt — the same "prove the mechanism, the panel is separate" split `rp-02`/`ls-e-01` already used |
| ls-i-01 ⚠ | **A product configurator.** The non-game `tpl-04` template ("viewer, configurator, device twin") with a real product: a step's annotation changes colour or material and shows price/specification alongside. Built, under `tpl-04`'s own honest boundary (tooling-plan.md §"tpl-04"): `configurator.json`'s `configurator-panel` annotation cycles three named variants and their price live, on tap — the "buyer changes a variant through an annotation... and sees the specification update" half of the acceptance is literally true today. The product's own geometry does not retint: `Brush` (`packages/flutter3d_sim/lib/src/level/brush.dart`) carries no name to address "this box" by, and a brush's material is baked into its mesh (and its lightmap, `lightmap_baker.dart`) at load rather than looked up live, so a real fix is a brush-addressing and live-remesh/relight change, not a widget change — out of scope for this row's own S estimate | steps, annotations, property binding | tpl-04, wg-01 | S | a buyer changes a variant through an annotation rather than a separate menu, and sees the specification update |
| ls-i-02 | **Incident review on an operator panel.** ⇢ demo `wg-02` ("an operator panel by the machine"), grown into a full lesson: an engineer rewinds through `rp-02` to the failure moment `edu-05` recorded as its own input tape, and works through "what the sensor showed → what the operator did → what happened" | a run, a timeline, steps | wg-02, edu-05, rp-02 | M | an engineer opens a recorded failure from a link and scrubs the timeline to the moment the lesson named |
| ls-i-03 ⚠ | **Maintenance instructions.** A real assembly's own housing teardown (content shared with `ls-e-04`) for a field technician: a cross-section shows the inside, steps give the disassembly/reassembly order | cross-section, steps, layer-by-layer disassembly | edu-01, prep-00 | S | a technician goes through disassembly and reassembly in the right order on a tablet with no network. Closed 2026-09-14 against this literal acceptance: `apps/flutter3d_lesson_viewer/assets/levels/housing.json` — a control box's own case, lid, circuit board and battery, seven `edu_step`s that remove the battery, board and lid in order and then put them back in the reverse order, proven the same way `ls-e-00`'s own teardown is (`housing_test.dart`, five tests: forward disassembly, then reassembly restoring exactly the part each step names, ending with every node visible again). No new code — `flutter3d_lesson_viewer` already opens any teardown-shaped document by asset path, and it already works offline once built, which is this row's own acceptance in full. **Not built**: an `edu_clip_plane` cross-section — the row's own description asks for one, no scene in this workspace has ever drawn one (`ls-x-00`'s own honest-scope line names the same gap), and the acceptance text itself never tests for it |

---

## 6. VR/XR (`ls-x-`)

| id | Scenario | Format | Depends on | size | Acceptance |
|---|---|---|---|---|---|
| ls-x-00 ⚠ | **An engine teardown in Cardboard.** ⇢ `edu-06`'s own acceptance: the same document as `ls-e-00`, opened in `StereoViewer`, stepping through with a button on the cardboard headset's own side panel. Built: a new app, `apps/flutter3d_stereo_lesson_viewer` — the same `LevelCubit`/`OpenKind`/`_addParts` trio already proven in `flutter3d_lesson_viewer`, with a `CameraNode` on a `StereoRig` and `LessonView` on the already-built `LessonStereoView` (which existed before this row, just with no app around it). Its own copy of `teardown.json`; five tests, all green (opening, refusing a file that does not exist, parts genuinely named and visible, a step genuinely hiding its own part and only that one, the screen genuinely reaching its buttons). The honest boundary is the same one `LessonStereoView`'s own doc comment already names: "nothing here has held a real folded holder up to a real phone" — proven headless, not on an actual Cardboard | the same document as `ls-e-00` | edu-06, ls-e-00 | S | the teardown plays in Cardboard on a student's own phone, stepping through with one button |
| ls-x-01 ⚠ | **A product configurator in stereo.** `ls-i-01` opened in `StereoViewer` — "try before you buy" in VR, the same document and the same property binding. Its own real prerequisite closed 2026-09-14, not this scenario itself: `WidgetSurface` (`wg-01`) had never been resolved or ticked inside any stereo application — `LessonStereoView`/`StereoSurface` already draw any `Scene` handed to them with no node-type special-casing, so the gap was purely that `apps/flutter3d_stereo_lesson_viewer` never built a `WidgetSurfaceVisuals` from a level's `widget_surface` entities or called `tick()` on it once a frame. Both are wired now (`LessonStereoView` gained an `onTick` hook), proven with a real `widget_surface` in that app's own shipped `teardown.json` (`title-card`, a static caption) and a test confirming it resolves onto the scene. **Not done**: `ls-i-01`'s own `configurator.json` is not opened by the stereo app at all, and the configurator's own annotation needs a *tap* to change anything — no ray from a stereo camera pair has ever been cast at a `WidgetSurface` here; `wg-00`'s own "ray → uvAt → dispatchAtUv → a tap" chain is proven flat only. Both remain real, separate work | the same document as `ls-i-01` | edu-06, ls-i-01 | S | the same configurator plays in a headset, the annotation works through the same input `wg-00` already measured on a phone |
| ls-x-02 | **First-person racing in stereo with HUD widgets.** The racing demo in `StereoViewer`, the HUD (position, lap, car state) drawn as widgets on a surface inside the headset — a showcase for tooling-plan.md's own second bet (Flutter widgets on 3D surfaces) under the most demanding input-and-repaint conditions there are | widget on a surface | wg-01, flutter3d_stereo | M | the HUD reads cleanly in a headset with no stutter; the stereo repaint cost measurement is added to `wg-00`'s own table in tooling-plan.md §8 |
| ls-x-03 | **Remote training on a twin.** `ls-i-00` opened in `StereoViewer` for remote instruction: the same machine, the same data tape, a first-person view instead of a screen | the same document as `ls-i-00` | edu-06, ls-i-00 | S | the same "what if" from `ls-i-00` reproduces in a headset, the branch is visible the same way |

---

## 7. Order

- **Now, with no code:** `prep-00`…`prep-03` (§2) — alongside writing `edu-00`
  in tooling-plan.md, so the format is designed with real content in mind
  rather than in the abstract.
- **Once `edu-00` (S) closes, before `edu-01` (L):** nothing in this plan can
  be assembled yet — the authoring tool does not exist. `edu-00` is the
  document, `edu-01` is the tool it is assembled through.
- **Once `edu-01` closes:** `ls-e-00`, `ls-e-04`, `ls-i-03` — three scenarios
  that need neither `wg-01` nor broker data, only layer-by-layer disassembly
  and annotations.
- **Once `wg-01` closes:** `ls-g-01`, `ls-g-02`, `ls-g-04`, `ls-i-01` —
  scenarios on in-game surfaces and property panels.
- **Once `edu-05` closes:** `ls-i-00`, then immediately `ls-i-02` (the same
  twin, plus `rp-02`).
- **Once `edu-06` closes:** `ls-x-00`, `ls-x-01`, `ls-x-03` — the same
  document already assembled for a screen, opened in `StereoViewer`; each one
  S, since the content already exists.
- **`ls-x-02`** waits on `wg-01` and on nothing else in this plan —
  an independent branch, a showcase for the second bet in stereo.
- **`ls-g-00`, `ls-g-03`** wait only on `edu-00` and `tpl-02`/`edu-00`
  respectively — they do not wait on `wg-01`, and can be built first among
  the game scenarios.

---

## 8. Out of scope

- **A building or a site as a digital twin** (BIM, geospatial) —
  tooling-plan.md §7 already defers these until large-scene streaming
  exists; `ls-i-*` starts with a device for the same reason.
- **Multiple authors editing a lesson together** — tooling-plan.md §7, waits
  on team projects in the cloud.
- **A full multi-lesson course, student progress across lessons** — this
  plan is about individual scenarios, not an LMS-like sequence inside the
  engine itself; `edu-03` (LTI/xAPI) deliberately hands that role to a real
  LMS.
- **SCORM** — tooling-plan.md already deferred it "on a university's own
  request."
- **Localizing lesson text** — the first pass is one language per scenario;
  a second language is added the same way the rest of the site's content is,
  not by this plan.
