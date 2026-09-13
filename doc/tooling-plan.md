# Time as an object — the tooling breakthrough track's plan

Compiled 2026-09-11. Grounded in the owner's own 2026-09-11 decisions after
three rounds of questions (44 questions: on monetization, on tooling relative
to fscene.dev, on the breakthrough feature and non-game uses; answers in
§3). Everything said about the code was checked against the tree on the
`modeler` branch the same day.

Notation — as in [model-editor-plan.md](model-editor-plan.md) and
[asset-pipeline-plan.md](asset-pipeline-plan.md): **size** — how big for one
person (S up to a week, M two to three, L a month or more); **⚙** — an
engine change; **⇢ X** — an item absorbs item X from another plan or a
ROADMAP section. Packages: `sim` = `flutter3d_sim`, `session` =
`flutter3d_session`, `testing` = `flutter3d_testing`, `cpu` = `flutter3d_cpu`,
`net` = the new `flutter3d_net`, `editor` = `apps/flutter3d_editor`,
`modeler` = `apps/flutter3d_modeler`, `editor_mcp` = `flutter3d_editor_mcp`,
`cloud` = `cloud/server`, `site` = `site/content`, `build` =
`flutter3d_build` from the asset plan.

---

## 1. In short

1. **The bet.** One big bet, six months: recording, playback, scrubbing,
   branching and sharing runs, built into the runtime, the editors, the
   cloud and MCP. Rollback netcode, a bug report as a file, scrubbing with a
   level edit, an agent playtester, virtual labs and "what if" scenarios for
   twins all grow out of it. Neither fscene, nor Unity, nor Godot has this,
   because their simulations are non-deterministic; ours has proven,
   recorded determinism (`StateDigest`, `Demo`, `RewindBuffer` in `sim`).
2. **A second bet, in parallel.** Flutter widgets on 3D surfaces with input.
   The one feature an engine not built on Flutter cannot match; needed at
   once by a product viewer, an operator panel on a twin, and a teaching
   stand. `WidgetTexture` in `session` already draws a widget into a
   texture, but once, with no input.
3. **Parity with fscene is trimmed to three items**, without which the bet
   cannot be shown at all: hot reload for models and textures, a
   diagnostic MCP with a frame snapshot, agent skills for users.
   Downloadable editor builds, an IDE plugin and a store-publishing
   pipeline are deferred (§7).
4. **One document for three segments.** An "interactive" for an instructor,
   a product viewer and a twin's panel are one format: a model,
   layer-by-layer disassembly, annotations, steps, property-to-data
   bindings. Annotations and steps are ordinary widgets, which is the
   second argument for the second bet.
5. **The selling demo** (§6): two machines race over the network, a player
   sends a link to their run, the developer scrubs to the frame in the
   editor, edits the track, re-simulates, an agent runs two hundred races
   overnight with no GPU and hands back a report. No other engine can shoot
   this video.
6. **Timing.** Two tracks for two people plus agents. Each track's critical
   path is ≈ 16 weeks (§5); both fit inside half a year. The sum of every
   code item is 14 S, 15 M, 3 L ≈ 66 weeks for one person with no
   parallelism.

---

## 2. What exists now

| What | Where | State |
|---|---|---|
| A fixed step and loop | `FixedStep`, `GameLoop` in `sim/loop/` | exists, no Flutter |
| A state snapshot | `Snapshot` in `sim/save/snapshot.dart` | exists; restores into already-existing objects — restoring into a freshly loaded level is the caller's own job |
| An input tape | `InputTape`, `InputTapeRecorder`, `InputTapePlayback` in `sim/input/input_tape.dart` | exists; transitions, not holds, an axis every step |
| A run as a file | `Demo` in `sim/save/demo.dart`, `DemoFile` in `flutter3d_screens` | exists: a snapshot + a tape; stored on the platform next to a save |
| Scrubbing | `RewindBuffer`, `RewindPoint` in `sim/save/rewind.dart` | exists: a keyframe once a second, steps between them, `cut()` for a branch; used for the kill-cam |
| A digest and a trace | `StateDigest`, `DigestTrace` in `sim/save/state_digest.dart` | exists; an IEEE-754-bit hash, stable between the VM and the web by design |
| A ghost | `Tape`, `Recorder`, `Playback` in `sim/save/` | exists; positions, not the simulation — survives tuning |
| A frame with no GPU | `renderFrame` in `testing`, `CpuDevice` in `cpu` | exists; pixel tests for a game on a machine with no graphics card |
| A widget into a texture | `WidgetTexture` in `session/widget_texture.dart` | exists; its own `BuildOwner` and `PipelineOwner`, draws once, no input |
| A running game | `RunSession`, `RunPlaying` in `session` | exists; the editor holds a live level the same way |
| MCP servers | `editor_mcp`, `flutter3d_model_mcp` | exist; stdio, one document per process, no window and no GPU; connecting to an open editor is on the ROADMAP |
| Stereo | `StereoRig`, `StereoSurface`, `StereoViewer` in `flutter3d_stereo` | exists; `flutter3d_xr` is an empty directory holding build junk |
| Rigid bodies | `RigidBody`, `dynamics.dart` in `flutter3d_physics` | no rotation and no joints, deliberately; the second phase is "after the quarter" |
| The cloud | `cloud/server` | an account, models, a model page, a blob by SHA-256; no runs and no commands |
| Editor web builds | `apps/flutter3d_editor/web`, `apps/flutter3d_modeler/web` | exist |
| The site | `site/content/{core,platformer,racing,shooter,strategy,reference}` | genre guides and tutorials; no live demos inside the guides |
| Networking | — | nothing; lockstep is the ROADMAP's second-tier item 2 |
| Checking the plans | `tool/verify_plan.dart` | reads only `model-editor-plan.md`; this plan, like the asset plan, is invisible to it |

---

## 3. The decisions this plan is built on

Made by the owner on 2026-09-11. Three rounds of questions; only what
changes tooling is here. Monetization decisions enter as constraints.

| Question | Decision |
|---|---|
| The breakthrough feature | **One big six-month bet**, parity gets trimmed; the target audience is game developers, including ones not from Flutter |
| Determinism-based candidates | **All four**: rollback netcode, scrubbing with a bug report as a replay, an agent playtester, golden tests and server-side rendering |
| Authoring candidates | **All four**: collaborative editing, widgets in 3D, live data in a scene, lessons inside the editor — but this plan covers only widgets and live data; collaborative editing and lessons are §7 |
| Parity with fscene in 3 months | All four chosen; **the plan keeps three** (hot reload, diagnostics, skills) and defers downloadable builds |
| Templates | `init --template=<genre>`, a wizard in the editor, non-game ones, from the cloud — **in this order**, non-game ones after widgets |
| Examples | **A gallery of live browser demos with an "open in the web editor" button** |
| The showcase | Four demos **on the web right away**, stores follow |
| Education | An interactive from the modeler with no code, an LMS, virtual labs, stereo — **all of them**; universities, schools, corporate training, online platforms come first |
| Twins | A device, a building, a territory, "what if" — **all of them**; the plan starts with a device and "what if," a building and a territory are §7 |
| Other uses | Robotics, medicine, architecture, scientific graphics — keep in view, no dedicated items |
| License and agents | MIT forever; MCP is free, the user's own LLM; the game backend is **self-hosted, open source** |
| Content | A series, short clips, shorts, streams; **two channels at once**; every platform; a game jam, bounties, a showcase, a monthly report |

---

## 4. Items

### 4.1 A run as an object (`rp-`)

| id | What | package | size | depends | acceptance |
|---|---|---|---|---|---|
| rp-00 | **Spike: determinism across platforms.** `DigestTrace` from four demos is recorded on a macOS VM, in the browser (dart2js and wasm), on Android and iOS from one tape; a divergence is named by step. The libm divergence from the ROADMAP enters here as the first known case | sim, apps | S | — | a "demo × platform → matched / first diverging step" table in §8; if it diverges, the cause is named and a fix item is opened before net-01 starts |
| rp-01 | **The run file.** `Demo` gets a format version, a reference to the level with its own hash, a build stamp, checkpoint digests every N steps and optional metadata (platform, who recorded it). Extension `.f3drun`. The writer and reader live in `sim`, with no Flutter; `DemoFile` in `screens` writes this format | sim, screens | S | rp-00 | a file from one game reads with `dart run`, no Flutter; a file from a newer format version is refused with a suggestion; a "write → read → replay → same digests" test on each demo |
| rp-02 ⚙ | **A timeline in the editor.** A panel over `RunPlaying`: pause, step, scrub through `RewindBuffer`, a scrubber across the whole run from `.f3drun`, checkpoint-digest markers; a branch through `cut()` — a new tape from the point. The same commands MCP will get | editor, session | M | rp-01 | a person scrubs a demo back to 3 seconds before death, releases — the game continues from that same state; the branch is written as a separate file; commands are visible in history |
| rp-03 ⚙ | **Re-simulating after a level edit.** A snapshot restores into a reloaded level: entities are matched by name and order, whatever the new level lacks is dropped with a message, whatever is new starts from the document. Answers the ROADMAP's own "replay has to survive the swap"; **⇢ level hot reload** from there | sim, editor | M | rp-02 | a person moves a wall in the editor while paused, the run continues from the current point against the new geometry; a level with a monster removed doesn't crash and names what was dropped |
| rp-04 | **A bug report as a run.** In-game: "send run" writes a `.f3drun` with the last N seconds from `RewindBuffer`, digests and a build stamp; opened by double-clicking in the editor (a file association, drag-and-drop on the web build); in the cloud — an upload under an account, a link, a download. The cloud does **not** replay: it has no game code | screens, editor, cloud | M | rp-01, rp-02 | a run from a phone opens by link in the editor on a laptop at the same step it was on the phone (digest matches); the run's page shows the level, its length, the platform, the stamp |
| rp-05 | **A run into video and into a test.** `dart run flutter3d:replay file.f3drun --video out.mp4` renders every frame through `renderFrame` via `cpu` and stitches them with ffmpeg; `--check` compares digests and names the first diverging step; `replayGolden()` in `testing` is a golden test of run frame N. **⇢ "server that verifies a run by replaying it"** from the ROADMAP, as self-hosted CI for the project. The mechanism under all three items is built and passes: `apps/flutter3d_demo_dungeon/test/replay_video_test.dart` — a real playthrough of the crypt, `--check` matches on an honest recording and names the step on a corrupted one, `--video` actually calls `ffmpeg` and gets a non-empty file back; `test/replay_golden_test.dart` (this edit) — a recorded, committed `test/goldens/replay-frame.png`, a second run is compared against it rather than overwriting it, and the same tape, played twice from scratch, draws the same bytes both times. Not through `replayGolden()` literally — that one asks to assemble a scene for a FRESH device inside `frame:`, while here the scene already exists and has already stepped; `expectMatchesGolden` is called directly on the frame from the very same `_drawOne` that `--video` already draws with, which is the more honest choice — a fresh load from scratch would know about the level document, not about wherever the tape has driven the player and the monsters. `dart run flutter3d:replay` in the literal form is unreachable without editing `flutter3d_game`'s own pubspec: a real run's genre package pulls in `flutter3d_game`, and that one names `flutter: sdk: flutter` for real, not for one type alone — `desktop_input.dart`, every `touch_*.dart`, `playing.dart`, `accommodations.dart` really import `package:flutter/...`, so a plain `dart run` fails compiling the framework itself before a line of user code — the same wall `flutter3d_sim_mcp`'s own pubspec already pins down in its own line, "checked empirically, the same way `rp-05` found it out for genre packages generally." A CLI wrapper around the already-finished mechanism is `ap-10`'s `flutter3d_build`'s job, once it exists | build, testing | S | rp-01 | a 30 s race video from CI with no GPU; a test that "run frame 600 matches the reference" in one of the demos; `--check` on a tampered tape names the step |
| rp-06 | **A per-run-step profiler.** ⇢ the ROADMAP's "Measurement" section: a counter trace per pass, keyed by run step; a frame-time strip above the scrubber in rp-02's timeline | sim, editor | S | rp-02 | a trace per step; a frame-time spike is visible on the strip, and a click on it jumps to the step |

### 4.2 Networking on determinism (`net-`)

| id | What | package | size | depends | acceptance |
|---|---|---|---|---|---|
| net-00 | **Spike: the cost of a rollback.** Restore `Snapshot` and re-run k steps for all four demos on a mid-range phone, k = 1…10; the budget is 8 steps in 4 ms. If it doesn't fit — what's expensive (the snapshot, the step, allocations) and an item to fix it | sim, apps | S | rp-00 | a "demo × k → ms" table in §8; either the budget is met, or an item is opened |
| net-01 | **`flutter3d_net`.** Flat Dart over `sim`: input frames per step, input delay, prediction from the last frame, rollback on confirmed input, a digest at a checkpoint step, a desync named by step. The transport is an interface; tests use a loop with delay and loss | net | L | net-00, rp-01 | two simulation instances in one test, through a loop with 120 ms delay and 5% loss, converge by digest; swapping input on one side gives a desync with a step number |
| net-02 | **Relay and transport.** `flutter_webrtc` (or an equivalent) as the primary transport — data travels P2P between players rather than through a server; the relay is `dart run flutter3d_net:relay`, one process, code-based rooms, no accounts, its role narrowed to signaling (SDP/ICE exchange) and a TURN fallback for NAT pairs that can't negotiate directly. WebSocket stays a fallback transport behind the same net-01 interface, for a platform or network where WebRTC won't build or won't get through. A `systemd` unit and a Dockerfile sit alongside it. **⇢ the ROADMAP's second-tier item 2**; self-hosted, per §3's decision | net | M | net-01 | two browsers on different machines negotiate through a relay on a VPS and then exchange input frames directly (P2P), with no game traffic passing through the relay; delay and loss show in the console; the relay goes down — signaling is unavailable, the game doesn't hang; behind a NAT requiring TURN, the connection still establishes |
| net-03 | **Racing for two.** The racing demo gets a "create / join by code" screen, the second player's input comes over net-01, a ghost (`Playback`) stands in for the opponent before they connect; the match's run is written as `.f3drun` from both sides | apps | M | net-02 | two phones play a race over Wi-Fi through a relay; both run files give matching digests; the race video is §6's first scene |
| net-04 | **Diagnosing a desync.** `dart run flutter3d_net:diff a.f3drun b.f3drun`: the first diverging step and a per-entity snapshot diff at it | net | S | net-01 | on two runs with swapped input, names the step and the entity |

### 4.3 An agent plays (`ai-`)

| id | What | package | size | depends | acceptance |
|---|---|---|---|---|---|
| ai-00 | **`flutter3d_sim_mcp`.** A third server, stdio: open a level, step N steps with input, a snapshot in words (positions, health, events), a digest, a PNG frame via `cpu` with a chosen camera, write a `.f3drun`. The same code rp-05 uses | a new package | M | rp-01, cpu | an agent from Claude Code clears the crypt's first room by frames and words and hands back a run that opens in the editor |
| ai-01 | **Playtesting in batches.** `dart run flutter3d:playtest level.json --runs 200 --policy random\|agent`: runs in isolates with no GPU, a report: where they got stuck, where they died, where they never reached, a heatmap in JSON | build | S | ai-00 | 200 crypt runs overnight on a laptop; the report opens in the editor as a layer over the level |
| ai-02 | **A report layer in the editor.** ai-01's heatmap and death points over the level; clicking a point opens the run at that step | editor | S | ai-01, rp-02 | a death point → the timeline at that step |

### 4.4 Widgets on surfaces (`wg-`)

| id | What | package | size | depends | acceptance |
|---|---|---|---|---|---|
| wg-00 | **Spike: input and redraw.** A ray from the pointer → a hit → a UV → a coordinate on the `RenderView` `WidgetTexture`; a `PointerEvent` into its own `BuildOwner`; a redraw only when the widget has marked itself dirty; measuring the frame cost of redrawing 512² on a phone and in the browser (canvaskit and skwasm) | session | S | — | a button on a wall taps under a finger on a phone; a "platform → ms per redraw" table in §8 |
| wg-01 ⚙ | **`WidgetSurface`.** A scene node: a live widget, redraw by dirtiness, pointer and focus routing, a keyboard while focused, semantics in §7. In the level document — a reference to a widget by name from the application's own registry | session, sim, editor | L | wg-00 | a text field on an in-game screen accepts keyboard input; a list scrolls under a finger; a frame with no widget change doesn't redraw it (a counter in the diagnostics) |
| wg-02 | **A demo.** A terminal in the crypt with a run's own event log; an operator's panel by a machine in the twin template (edu-05). Both scenes are built: `RunTerminal` is wired into `flutter3d_demo_dungeon`'s own widget registry (`'run-terminal'`), `OperatorPanel` now lives in `flutter3d_template_app` and draws `tpl-04`'s `twin.json`'s `'twin-dashboard'` — a real, live temperature from `edu-05`'s `SamplerDataSource`, not a stand-in. The literal acceptance is honestly not fully closed: `site/content/gallery.md`'s own gallery embeds only the four games, not `tpl-04`'s templates, so the operator panel is only visible inside the template application itself today, not on the `tpl-02` page | apps | S | wg-01 | both scenes are in the tpl-02 gallery |

### 4.5 The parity that remains (`par-`)

| id | What | package | size | depends | acceptance |
|---|---|---|---|---|---|
| par-01 ⚙ | **Hot reload for models and textures.** ⇢ the ROADMAP's "The editors reach the running game"; builds on ap-05 and ap-11 from the asset plan: a saved file is rebuilt by the hook's own code and swapped in through the VM service | build, engine, editor | M | ap-11 | a model saved in the modeler shows up in the demo on a phone with no restart |
| par-02 | **A diagnostic MCP.** ⇢ the same ROADMAP entry: a viewport/window snapshot, debug views, any pass's own output, an HDR pixel value, a scan for the first NaN in a pass. A frame with no GPU — via ai-00 | editor_mcp, a new package | M | ai-00 | an agent names the pass that turns a deliberately broken normal map black |
| par-03 | **`dart run flutter3d:skills`.** Writes skills for the engine's own users into a project: idioms, quiet traps, light and post-processing, performance, runs and networking. ⇢ the ROADMAP's second-tier item 8 | build | S | — | running it again is an empty diff; an agent with the skills gets through the quickstart with none of the mistakes the skills describe |

### 4.6 Templates and the gallery (`tpl-`)

| id | What | package | size | depends | acceptance |
|---|---|---|---|---|---|
| tpl-01 | **`init --template=<genre>`.** The four demos become templates: `dart run flutter3d:init --template=platformer\|racing\|shooter\|strategy` writes a project with a level, assets under `assets_src/` and a hook from ap-10; `--list` names the templates | build, apps | M | ap-10 | a clean `flutter create` + `init --template=racing` + `flutter run` gives a playable race on macOS and in the browser; templates build in CI |
| tpl-02 ⚠ | **A gallery of live demos.** A site page with web builds of the four games and scenes from the guides; each carries "open in the web editor" with the level by URL and "download the run." Builds come from CI, not by hand. The platformer and racing entries are done: each already had a `test/demo_test.dart` proving a byte-for-byte replay of its own shipped level — `tool/record_sample.dart` in each app calls the same route and writes `site/assets/samples/{platformer,racing}.f3drun` instead of only checking against it. Strategy honestly gets no recording: `.f3drun`'s own tape is `GameAction`'s continuous state (pressed/analog), while a match is played through discrete orders via `CommandPost` (`TrainOrder`, `restock`), which `main.dart` never turns into an `InputState` at all — a second kind of tape frame is needed, not a third `record_sample.dart` | site, editor | M | net-03 | the gallery opens on a phone; a button opens the level in the web editor; a lighting guide embeds a live scene |
| tpl-03 | **A "new project" wizard in the editor.** A template, a name, platforms → `init` under the hood → the opened level | editor | S | tpl-01 | a project is created with no terminal on macOS; in the browser the wizard honestly says it does not run a build |
| tpl-04 | **Non-game templates.** A viewer, a configurator, a device twin — over the edu-00 document and `WidgetSurface` | build, apps | M | wg-01, edu-01 | three templates in `--list` and in the gallery |

### 4.7 One document for education, product, and a twin (`edu-`)

| id | What | package | size | depends | acceptance |
|---|---|---|---|---|---|
| edu-00 | **The interactive's specification.** On top of the level document, no second scene format: steps (camera, visibility, highlight), layer-by-layer disassembly (a node offset at a step), annotations (a widget by name), cross-sections (a clipping plane), bindings of a node's properties to named data sources, a checked question. Written into `doc/` as a format, ahead of the code | doc, sim | S | — | the document has been read by two people with different backgrounds (an instructor, an engineer), their notes folded in |
| edu-01 ⚙ | **Authoring in the web modeler and the editor.** A step panel, drag-to-disassemble at a step, an annotation as a widget, a clipping-plane gizmo; all through commands, meaning through MCP too. The step panel is already built and covered by tests: `apps/flutter3d_editor/lib/src/step_panel.dart`'s `StepPanel`, wired into `main.dart`, nine scenarios in `step_panel_test.dart` (add/reorder/delete a step, attach an annotation, drop a clipping plane) — all through `Place`/`SetField`/`Delete`, meaning through MCP too (`lesson_authoring_mcp_test.dart`). `edu_annotation`/`edu_clip_plane` in the editor are ordinary entities with no visual of their own (the widget and the cross-section are actually drawn by `flutter3d_lesson_viewer`, not the editor — authoring is blind, the preview is a separate application). "Drag-to-disassemble" closed a different way than this row itself assumed: `ls-e-00`, the first real content on this format, disassembles an engine as four separate entities (`engine-block`/`valve-cover`/`air-filter`/`spark-plug`), not one model with named nodes inside it — and a separate entity is already moved today by an ordinary `AxisDrag`/`MoveBy`, with not one new line of code. `mergedOffsets(step, nodePath, delta)` in `lesson_authoring.dart` is arithmetic for a DIFFERENT, hypothetical case (one glTF with `valve_cover` as an internal node) that not one real lesson uses yet; the node `engine-body#valve_cover` itself is an example from a doc comment and a test, not from actual content. Picking exactly that kind of internal node is technically possible already today — `scene_dressing.dart`'s `dressGizmos` calls `asset.instantiate()` and puts the model's real root into `owners` for picking — but building an interface for a data shape nothing uses would be work with no scenario behind it (an owner decision, made after checking, not before). `editor_inspector.dart`'s own `_byType()` still draws a Map as `_ReadOnly` — there's nowhere to type `offsets` in by hand except MCP's `setField` or a test, but that is no longer the gap this row is meant to close | modeler, editor | L | edu-00, wg-01 | an instructor assembles a five-step engine teardown in the browser with no code and gets a link |
| edu-02 | **A public page and an embed.** An interactive's own page on models.pleion.dev, an iframe with parameters, a viewer as a web build on the engine | cloud | M | edu-01 | the interactive is embedded in a Stepik course page and in a GitHub README through an iframe |
| edu-03 | **LTI 1.3 and xAPI.** The cloud as an LTI tool: launched from Moodle and Canvas with a student's identity, answers to a step's question become xAPI statements in the course log. SCORM — on a university's own request, not here | cloud | M | edu-02 | the interactive launches from a test Moodle; the grade for a question is visible in the log |
| edu-04 | **A virtual lab.** A level with a parameter panel (`WidgetSurface`), the run is written as `.f3drun`, checked by digests at checkpoint steps against a reference tape; an instructor opens a student's run in rp-02's timeline | sim, apps | M | rp-02, wg-01 | a pendulum: a student changes the length, the result reproduces on a school laptop with no GPU, the instructor sees exactly where the student went wrong |
| edu-05 | **Live data in a scene.** MQTT and WebSocket sources as named streams; binding a node's property to a JSON path in the inspector; a history of values is written into the tape as input, meaning the twin scrubs and branches like a game does | sim, editor | M | edu-00, rp-02 | a machine from the tpl-04 template shows temperature from a broker; "what if" is a branch from the current step with a substituted value |
| edu-06 | **Stereo for a classroom.** `StereoViewer` opens an edu-00 interactive: Cardboard on a student's phone, the same document | flutter3d_stereo | S | edu-01 | an engine teardown in Cardboard, switching steps with a button |

### 4.8 Content and community (`out-`)

Not code; sizes are weeks of presence, not development. Every video, post
and talk ends with a link to a run or the web editor, not the repository.

| id | What | when | acceptance |
|---|---|---|---|
| out-01 | **Two channels.** Russian and English; a "racing from scratch to networked" series, 8–12 episodes of 20–40 minutes, short feature clips of 3–8 minutes, shorts cut from gallery footage, net-01 development streams | from month 1 | an episode every two weeks on each channel; every episode links to a run |
| out-02 | **A monthly report.** What got done, what didn't land, the numbers; a post and a video | from month 1 | six reports |
| out-03 | **Venues.** English-language Flutter podcasts and channels, Russian-language podcasts and conferences, a FlutterCon talk, r/gameenginedevs with a run as proof | submissions from month 2 | four appearances over half a year, one with a talk |
| out-04 | **A game jam.** Announced once net-03 works: "a networked game in 48 hours," tpl-01 templates, a relay set up by the organizer, results — participants' runs in the gallery | month 5 | at least ten submitted games; their runs open in the editor |
| out-05 | **Bounties and good-first-issues.** A Blender exporter, gallery examples, skills | from month 2 | five closed bounties |
| out-06 | **A "built with flutter3d" showcase.** A site page; a submission is a link to a run or a web build | month 3 | the jam's games are the first entries |

---

## 5. Order and the critical path

Two tracks for two people; agents take what's marked below.

- **Track A — time and networking.** rp-00 → rp-01 → rp-02 → rp-03 → rp-04,
  and from rp-00 in parallel net-00 → net-01 → net-02 → net-03 → net-04. The
  critical path is **rp-00, net-00, net-01, net-02, net-03, tpl-02**: 2 S +
  L + 3 M ≈ 16 weeks at the upper bound (L here is six weeks). rp-02 and
  rp-03 run between them, because net-01 is the longest item and doesn't
  occupy the editor.
- **Track B — widgets and the document.** wg-00 → wg-01 → wg-02, then
  edu-00 (written during wg-01) → edu-01 → edu-02 → edu-03; edu-04 and
  edu-05 come after rp-02 from track A. The critical path is **wg-00,
  wg-01, edu-01, edu-02**: S + 2 L + M ≈ 16 weeks.
- **Items that hand off well to agents:** rp-01 (a format with a "round
  trip" test), rp-05 and net-04 (pure computation with a numeric
  acceptance), par-03, tpl-01, tpl-03, edu-06, documentation. **Poorly:**
  rp-00, net-00, wg-00 — the answer depends on device behavior; net-01 is
  the architectural core.
- **By month.** 1: rp-00, net-00, wg-00, rp-01, par-03, out-01–02.
  2: net-01 begun, rp-02, edu-00, tpl-01. 3: net-01, rp-03, wg-01, ai-00.
  4: net-02, rp-04, wg-01, par-02, ai-01. 5: net-03, edu-01, rp-05, out-04.
  6: tpl-02, net-04, edu-02, wg-02, ai-02, par-01, edu-04, the §6 video.
- **The September 28 ROADMAP review** accepts this plan whole or trims it
  per §7; "Committed" gets §4.1–4.5, the second tier gets §4.6–4.7.

---

## 6. The demo that sells

One six-minute video, each scene a plan item with its own acceptance:

1. Two phones race through a relay on a VPS (net-03).
2. On one, the race breaks off against a wall that shouldn't be there; the
   player taps "send run" (rp-04).
3. On the laptop, the link opens the run in the editor at the same step;
   the scrubber goes back three seconds (rp-02, rp-04).
4. The wall is moved while paused, the run continues on the new track
   (rp-03).
5. `flutter3d:playtest --runs 200` runs overnight; in the morning the
   heatmap in the editor shows there's nowhere left to get stuck (ai-01,
   ai-02).
6. `flutter3d:replay --video` renders the race with no GPU in CI, and that
   video is the clip's own last frame (rp-05).

Not one scene needs anything outside §4; if a scene can't be shot, the item
isn't accepted.

---

## 7. What gets trimmed, and why

- **Downloadable editor builds with a toolchain.** The web editors already
  answer "install nothing" better; a self-updating build for three OSes is
  M apiece and support forever. Revisit once tpl-03 shows demand for
  desktop.
- **An IDE plugin and a store-publishing pipeline.** A convenience, not a
  reason to choose the engine. After half a year.
- **Real-time collaborative editing.** Chosen by the owner, but needs a
  CRDT over the document and team accounts from the cloud track; L, and
  depends on things that don't exist yet. A future plan, once team
  projects exist.
- **Lessons inside the editor.** The same reason: they build on edu-00 and
  wg-01, which don't exist yet; a future plan.
- **A building (BIM) and a territory (geo) as twins.** Needs large-scene
  streaming and LOD, neither in the tree; starting with a device (edu-05).
- **Semantics for `WidgetSurface`.** An accessibility tree for a widget in
  3D is a separate question; wg-01 ships without it, recorded in the
  CHANGELOG.
- **Rigid bodies with rotation and joints.** Stay "after the quarter": not
  one §6 scene needs them; racing already drives without them.
- **Gaussian splats** (fscene has them). Don't affect a single §6 scene.
- **Comparison tables against other engines.** Stay in the ROADMAP's own
  "Not doing"; the comparison here is only this file's §2 and the §6
  video.

---

## 8. Spike results

Filled in as results come in: rp-00 — a "demo × platform → matched / first
diverging step" table; net-00 — "demo × k → ms"; wg-00 — "platform → ms per
512² redraw." Until the rp-00 and wg-00 tables close with a zero in the
divergence column, net-01 and wg-01 do not start.

### rp-00: determinism across platforms

Closed 2026-09-12. A thousand steps per demo, a digest every 25–30 steps
(`DigestTrace`), the same procedural input tape (a `GameRandom` seed) on
every platform — code in
`packages/flutter3d_game_*/test/parity_test.dart` and mirrored in
`apps/flutter3d_demo_*/integration_test/parity_test.dart` for Android and
iOS, where `flutter test` doesn't run (only the VM host and the browser do
— a real device needs `integration_test`). The platformer and shooter
scenario is new, written specifically for this spike; racing and strategy
inherited an already-existing `parity_test.dart`, extended here only with
checks on wasm and on mobile platforms.

| Demo (genre) | macOS VM | Chrome dart2js | Chrome wasm | Android (emulator, arm64) | iOS (simulator) |
|---|---|---|---|---|---|
| platformer | matched | matched | matched | matched | matched |
| racing | matched | matched | matched | matched | matched |
| shooter (dungeon) | matched | matched | matched | matched | matched |
| strategy | matched | matched | matched | matched | matched |

**No divergence at all.** Fifteen runs (plus the baseline recording —
twenty), every digest matched on the first try, not one fix item opened.
`net-01` can start.

What's outside this spike's own scope and unmeasured: a below-mid-range
device (measuring the cost of a rollback is net-00's own separate
question, not rp-00's), the real content of the shipped levels (the
scenarios are played in a synthetic room,
`flutter3d_sim/test/parity_test.dart`, not through `Level.fromJson` —
representative of step arithmetic, not of the level loader), and a
standing place in CI (`tool/ci.sh` today doesn't run these files in the
browser, on wasm, or on mobile at all — only on the VM through the shared
`flutter test` cycle; whether to add a browser/wasm/mobile step there
permanently, or whether it's enough that they exist and run by hand before
a review, is a question this spike doesn't settle).

### net-00: the cost of a rollback

Closed 2026-09-12, with an honest caveat about what it was measured on.
`restore()` + k steps, k = 1…10, on a real shipped level/track/match of all
four demos (not the synthetic room of `parity_test.dart` — a real game's
own snapshot and step carry an inventory, an automap, an economy, a crowd,
not just a controller):
`apps/flutter3d_demo_{dungeon,platformer,racing,strategy}/test/rollback_cost_test.dart`.
The snapshot is taken at step 300 (the game mid-swing, not an empty start),
the timer covers only the `k` steps after `restore()`, twenty samples per
k, the measurement itself prints numbers rather than checking them against
a threshold — the same trick `wg-00`'s own benchmark already uses: the
number depends on the machine, and net-00's budget is worded for "a
mid-range phone," which this session doesn't have — only a macOS VM (Apple
Silicon).

| Demo (genre) | k=1 | k=8 (budget: 4 ms) | k=10 |
|---|---|---|---|
| platformer | 0.28 ms | 1.92 ms | 2.29 ms |
| racing | 0.03 ms | 0.14 ms | 0.15 ms |
| shooter (dungeon) | 0.27 ms | 4.74 ms | 4.82 ms |
| strategy | 1.65 ms | 13.50 ms | 16.22 ms |

**Racing and platformer hold the budget with a large margin; dungeon is on
the edge, and strategy misses it by almost four times — and the two miss it
in different ways, exactly what the acceptance format asked for ("what's
expensive").**

- **strategy** — not a one-off spike, but an honest linear cost: every
  extra step costs ~1.6–1.8 ms regardless of k, meaning what's expensive
  isn't `restore()` (it sits outside the timer) or any one particular
  step, but the match step itself — the crowd, the economy and every
  unit's own `Bot` are recomputed every tick, and this is the only one of
  the four demos simulating not a single actor but a hundred and fifty
  (see `playthrough_test.dart`: a map starts with at least 120 units). On
  a mid-range phone this will be worse, not merely proportionally worse —
  a fix item: an incremental match step (recompute only what actually
  changed during the rollback frame) or lowering the economy's own
  recompute rate relative to the network step.
- **dungeon** — a different shape: k=1 costs 0.27 ms, k=2 already costs
  4.5–4.8 ms, and it's flat all the way to k=10 (~4.6–4.8 ms for ANY k from
  2 to 10). So what's expensive isn't gradually accumulating step work, but
  something that happens exactly once, exactly on the second step after
  `restore()`, and is not `restore()` itself (it sits outside the measured
  window). Caught honestly, but not all the way: the absence of
  `input.endStep()` between measured steps (loop hygiene — fixed in the
  test, the number didn't change) and `GameLoop.advance`'s own ordering
  were both considered and ruled out as the cause. Plausible, but not
  profiler-confirmed, candidates — `Automap.reveal` diffing "what's been
  seen" after `restore()`, or the broadphase of `CollisionWorld` rebuilding
  after body positions teleported back rather than moving by a step. A fix
  item: profile `GameSimulation.step` right after `restore()`
  (`dart:developer`'s timeline or `Observatory`), rather than guessing
  further from `Stopwatch` — this session didn't go deeper, because further
  localization with no profiler would have become guessing, not a spike.

Not measured, under the same limitation as rp-00: a real mid-range phone.
The numbers above are a lower bound on what the budget will demand; on a
device, they'll only be worse.

### net-01: `flutter3d_net`

Closed 2026-09-12. A new package, flat Dart over `flutter3d_sim` (one
dependency: `flutter3d_sim`, no Flutter at all — the same trick
`flutter3d_physics` uses), landing sixth in ARCHITECTURE.md's own
publishing order, next to `flutter3d_game`.

**The transport is an interface, exactly as the plan asked.** `NetTransport`
— two methods, `send`/`listen`, a JSON-compatible map both ways; nothing in
it knows about WebRTC, WebSocket or a relay — those arrive in net-02.
`LoopbackTransport.pair(...)` is net-01's own "a loop with delay and loss,"
literally: a pair of transports with a fixed delay (rounded to whole steps)
and a loss determined by probability from one `GameRandom` shared by both,
so which messages are lost is reproducible by seed. Not a mock: a message
genuinely arrives later than it was sent, and part of it genuinely never
arrives at all.

**`NetSession` — per-step frames, input delay, prediction, rollback.**
Knows nothing of the genre: `captureLocalFrame`/`applyAndStep` read and
write whatever the calling code uses to represent its own input (a shared
`InputState`, a `VehicleInput` per player — it doesn't matter), the same
trick `RunTimeline` uses in accepting `stepSim`/`restore` with no questions
about what's inside. Delay is its own decision, applied not immediately but
after `inputDelay` steps — the same time the counterpart takes to receive
it. Until the other side's real frame has arrived, the step runs on
prediction (repeating the last confirmed one). Once it arrives — if it
matched, nothing happens; if not, `restore(the snapshot before this step)`
and `applyAndStep` again for every step from there to the present moment,
each time taking the already-known local frame and either the just-confirmed
or still-best-known remote one.

**A real hole was found and closed: sending a frame just once doesn't
survive a loss.** The first version sent a frame only in the one message it
was born in, and a test with 5% loss diverged at the very first checkpoint
— a step whose one message was lost is never confirmed and stays on
prediction forever. Fixed with redundancy: every message carries not one
frame but the last `redundancy` (eight by default), so a frame gets
through as long as at least one of the nine messages that ever carried it
isn't lost — under 5% independent loss, the chance of losing all nine is
vanishingly small.

**The second finding was in the test itself, not in `NetSession`.** A
digest taken from the live "now" right after a step catches both sides at
the exact moment each is still only guessing at the other's own recovery —
that isn't a desync, it's two people who haven't compared notes yet.
`onSettled` is a callback fired exactly when a step leaves the rollback
window and `NetSession` can never correct it again; the digest checkpoint
is taken from there, not from the current state.

Three tests in `flutter3d_net/test/net_session_test.dart`, all against
net-01's own §4.2 acceptance, literally: 120 ms of delay and 5% loss — both
clients converge by `DigestTrace.divergenceFromHex`, and both
`droppedCorrections == 0` (the rollback window is correctly sized for this
delay, not just "the test passed"); separately — a connection with delay
deliberately greater than `inputDelay`, so nearly every step really goes
through a rollback rather than through luck with timing (the same
`droppedCorrections == 0` confirms the rollback actually did its job,
rather than being sidestepped); and, most importantly — `_LyingTransport`
swaps one frame's value across all of its repeats at once (otherwise
redundancy alone would heal a single lie) — both clients diverge, and
`divergenceFromHex` names a step no earlier than the one where the lie
could possibly have taken effect.

Not done, deliberately, outside net-01's own acceptance (that's
net-02/net-03): not one real transport (WebRTC/WebSocket), not one live
game wired through `NetSession` — only a genre-agnostic toy step, the same
trick `RunTimeline` in rp-02 was first proven on a toy with. `NetSession`
today doesn't count more than two players — net-01's own wording and
acceptance also speak only of two.

### net-02: the relay and the transport

Closed 2026-09-12, at the level provable without a real VPS and without
two real devices — the same boundary rp-02 named for "an actively played
game in an open window": all the code was assembled and checked with a
real second process; not checked — a second real computer, a NAT, a real
TURN server.

**The fallback transport is real, and checked through a real relay, not a
mock.** `bin/relay.dart` in `flutter3d_net` — one process, code-based rooms
in the URL path (`/room/<code>`), no accounts: the first two sockets for a
code connect and get everything the other sends, verbatim and unparsed; a
third is rejected. `WebSocketTransport`
(`lib/src/websocket_transport.dart`) is a `NetTransport` over
`web_socket_channel` (not `dart:io`'s `WebSocket` directly, so the same
class builds for the web too). The test
`flutter3d_net/test/relay_test.dart` (`@TestOn('vm')`) brings up
`bin/relay.dart` as a real subprocess (the same trick
`run_timeline_extensions_test.dart` uses in rp-02), reads the port from its
stdout, connects two `WebSocketTransport`s through a real socket at
`ws://127.0.0.1`, and runs the same `NetSession` convergence already proven
on `LoopbackTransport` in net-01 through it — this time over a real relay
and a real network (local, but real), not a test-managed loop. The second
test — a third socket for an already-occupied room gets a close from the
relay, not silence.

**WebRTC is real code too, not a stub, but with an honestly named
boundary.** `flutter_webrtc` pulls in Flutter and native bindings on every
platform, so it can't live in `flutter3d_net` (flat Dart is the very reason
the package exists separately) — a new package, `flutter3d_net_webrtc`,
depends on both `flutter3d_net` (behind the `NetTransport` interface) and
`flutter_webrtc`. `WebRtcTransport.createOffer`/`.awaitOffer` is a real
SDP/ICE exchange over any `NetTransport` signaling channel (in production,
the same `WebSocketTransport` to the relay, only with its role narrowed to
the handshake — `bin/relay.dart` doesn't know and shouldn't know whose
bytes these are, game frames or SDP), `RTCDataChannel` carries the frames
themselves after the handshake. Built and actually checked with `flutter
analyze` against `flutter_webrtc` 1.6.2's real signatures (not guessed
from memory — not even one and a half fixes were needed after the first
attempt, everything matched on the first try). Two tests in
`flutter3d_net_webrtc/test/webrtc_transport_test.dart` honestly check what
can be checked with no second participant: both sides
(`createOffer`/`awaitOffer`) really reach the call to
`createPeerConnection` and break there against the same wall — `flutter
test` doesn't register the native WebRTC plugin, so a `MissingPluginException`
comes back instead of a real connection, the same class of break rp-02
named for "a real device."

**A `systemd` unit and a `Dockerfile` sit alongside it, as the plan
asked**, in `flutter3d_net/deploy/`: the unit uses the same confinement
(`DynamicUser`, `ProtectSystem=strict` and the rest) that
`cloud/deploy/flutter3d-models.service` already uses, trimmed to what the
relay needs — no secrets, no state on disk, so neither `StateDirectory`
nor `EnvironmentFile` is needed. The Docker image was **not built** — the
Docker daemon is unavailable in this session (`docker info` answers that
it isn't running); the file is written but unchecked, the same honest gap
rp-05 names for ffmpeg on a CI machine.

Not done, honestly: not one real P2P connection between two devices, not
one real VPS, no NAT, no TURN — net-02's own acceptance literally asks for
"two browsers on different machines through a relay on a VPS," and this
session has no means to bring up a second real computer or browser.

### net-03: racing for two — the mechanism is done, so is the screen, except a real second phone

Closed 2026-09-12, except for the honest boundary net-02 already named: the
networked race itself is real code, really checked on a real
`RacingSimulation`, and along the way found an architectural bug that only
a two-game check could have found, not a solo one. The "create / join by
code" screen, a ghost indicator, and writing `.f3drun` from both sides were
built in the same session, as a second pass.

**The screen.** `NetRaceSession`
(`apps/flutter3d_demo_racing/lib/src/net_race_session.dart`) — a thin layer
between `NetRace` and the UI: `create`/`join` connect to the relay at
`ws://.../room/<code>`, deciding `localCarIndex` exactly as net-03's first
pass already worded it — the room's creator is always car 0, whoever joins
is car 1; `randomRoomCode()` is five characters with no `0`/`O` or `1`/`I`,
because the code gets read aloud and typed on a phone keyboard.
`NetRaceScreen` is the screen itself: "Create room" / a code field + "Join,"
after connecting — the room code, a `connected` indicator (`race.connected`,
already existed on `NetRace`) and an "End race" button that hands the
assembled session back to the calling code through `onEnded` — whatever
save panel decides to do with it is not this widget's own business, the
same principle `PlaytestReportScreen` uses from ai-02. The "Race with a
friend" button is in `main.dart`, visible only before the season starts,
next to `TitleCard`, and does a `Navigator.push` into the new screen,
touching nothing in the single-player game's own live render loop (a
deliberate decision — wiring `NetRaceSession` into the single-player race's
own 3D view is not something this task takes on, honestly, not quietly).

**A separate `.f3drun` per side, not a shared one — and this is a
deliberate decision, not a shortcut.** `Demo` is one side's own input tape
against the state that tape alone replays; in a networked race, the
opponent's car is driven by the network, not a script, and no single file
can replay both cars alone. The task's own acceptance — "both run files
give matching digests" — is exactly what a pair of independently written
`checkpoints` (`DigestTrace`) can prove, with no shared file from either
side. `NetRaceSession.saveRunTo` writes with `File.writeAsStringSync`, not
`writeAsString` — the same finding already honestly recorded at rp-04:
an asynchronous write inside `flutter test` in this session's sandbox
hangs dead, with no exception and no timeout, while a synchronous one in
the same test returns instantly.

**A real finding while testing the screen itself, not only the mechanism.**
The first attempt tried to prove full convergence (creation + joining +
the ghost indicator flipping) directly inside `testWidgets`, luring the
second peer with a real socket from inside a tap handler. A bare
`Future.delayed`, run the same way, really hangs with no `tester.pump(duration)`
— expected, `flutter_test`'s own fake clock wants exactly that. But a real
socket connection from inside `testWidgets`, driven to completion by a
`pump(duration)` loop, and a `tester.runAsync` wrapped around it, both hang
dead; a separate REPL-like probe test killed the process after 45 real
seconds rather than giving an answer through logic. The conclusion isn't a
guess but a measured tool boundary: a real socket opened from inside a
widget's own event handler doesn't play to completion under `pump` in this
sandbox, whatever wraps the code from outside. The screen is therefore
tested on what's safely provable (instant state transitions — the starting
screen, the "connecting" state), and full two-side convergence and digest
recording are proven at the `NetRaceSession` level directly, through a
plain `test()` (the same trick already working reliably in
`net_race_test.dart`), not through `testWidgets`.

Three tests in `apps/flutter3d_demo_racing/test/net_race_session_test.dart`:
`randomRoomCode` never gives a character that's easy to confuse; creating
and joining through a real relay really converge on `localCarIndex`, run
460 steps, both write a readable `.f3drun`, and `divergenceFromHex` between
their `checkpoints` is `null`. Two tests in `test/net_race_screen_test.dart`
on the screen's safe half.

**`NetRace`** (`apps/flutter3d_demo_racing/lib/src/net_race.dart`) — not a
new mechanism, but `net-01`'s own `NetSession`, aimed at a real genre:
`captureDriverFrame`/`applyDriverFrame` are the same four lines that
`main.dart`'s own `_readDriver` turns into a `VehicleInput`, only into JSON
and back; `localCarIndex` says which of the two cars on the field this
device drives.

**A real finding, not made up for the report: both sides called themselves
car 0, and it wasn't the comparison that was broken — the race itself
was.** The first version hard-wrote local input into `inputs[0]` and
incoming network input into `inputs[1]`, on BOTH sides. So slot 0 on the
starting grid is "me" from both points of view at once, meaning two
devices weren't physically playing the same race at all: each saw itself
in the spot the other saw as its own. Hence `localCarIndex`, a required
constructor parameter — which physical car is mine is decided once at
connection time (whoever created the room is car 0) and never changes.

**A second finding — subtler, and one that would have gone unnoticed
without an honest two-process check: the first `inputDelay` steps are
asymmetric if "not connected yet" is decided differently for the local car
than for the remote one.** `NetSession`'s own input delay means the LOCAL
frame is also empty for the first `inputDelay` steps — it simply isn't
its turn to apply yet. The first version of `NetRace` substituted a fixed
"drive straight" frame for the ghost car only when the REMOTE frame was
empty, so side A believed for the first three steps "my car is stopped,
the other one is a ghost driving," and side B believed exactly the
opposite about those same three steps. And no network confirmation frame
ever addresses those three steps — the very first message that can arrive
at all is stamped step `inputDelay`, not 0, meaning `NetSession`'s own
rollback never touches them either. The asymmetry is permanently baked
into the physics. Fixed: the ghost is decided by whether the SPECIFIC
frame is empty (one's own or the other's), not by which slot it is — now
both sides agree that the first `inputDelay` steps have BOTH cars driving
as ghosts, rather than one of them standing still. Caught by diffing two
full JSON snapshots (not only hashes) during debugging — seeing a
difference in the fifth decimal place of a car's own position, not chaos,
which is what pointed to a tiny, systematic misalignment rather than
random data corruption.

Two tests in `apps/flutter3d_demo_racing/test/net_race_test.dart`: a real
relay, real sockets, 460 steps of a race between two genuinely
independently assembled `RacingSimulation`s (`ring.json`, both cars) —
converging by `DigestTrace` checkpoints, `droppedCorrections == 0` on both
sides; and a separate, fast regression test on `LoopbackTransport` (no
subprocess, milliseconds rather than 2 seconds) with `every: 1`, checking
exactly the symmetry of the first `inputDelay` steps — the test that would
catch exactly this finding immediately, if it ever came back.

Not done, under the same limitation as net-02: not one real second phone
over Wi-Fi, no real VPS. The race video (§6) is outside engineering scope,
a separate item.

### tpl-02: a gallery of live demos — built, no web editor and none is coming

Closed 2026-09-12, with one insurmountable, honest boundary named up front,
before any code, not found along the way: "open the level in the web
editor by URL" is literally unreachable, because `apps/flutter3d_editor`
has no web build at all — a deliberate desktop-only architectural
decision, not a gap (the app's own doc comment: "Desktop only, and that is
not an omission... unlike the three games there is no web build and no
backend to choose between," the reason being that the editor writes a file
back over itself, which a browser won't do). A web port of the editor is a
separate, much larger task, not this one.

**A real finding before a single new line of code: almost the whole
gallery mechanism already existed, only without the page that assembles
it.** `site/tool/demos.sh` already builds all four demos for the web
(`flutter build web --release --base-href="/demo/<name>/"`) directly into
`site/dist/demo/<name>/`; each of the four games already has its own page
with a live `<iframe class="demo-frame">`
(`site/content/{shooter,platformer,racing,strategy}/demo.md`). What was
missing was one page showing all four at once — `site/content/gallery.md`,
registered in `NAV` (`site/tool/build.mjs`) as `/gallery/`, using the same
`<div class="demo">` pattern the four demo pages already use.

**"Download the run" is a real file, not a stub.** One real `.f3drun`
(`site/assets/samples/shooter.f3drun`, 6.6 KB) was recorded through ai-00's
own real headless path (`SimSession.open`/`.step`/`.writeRun`, run through
`flutter test` — the same socket-instead-of-literal-stdio trick, since
`dart:ui` isn't available to a bare `dart run`), not written by hand.
Honestly not done: the platformer, racing and strategy each lack a
ready-made headless recorder outside their own test suites today
(`SimSession` is deliberately shooter-specific, see `### ai-00`) — their
own rows in the gallery say exactly that: "Sample run: not recorded yet,"
rather than linking to a file that would quietly go stale.

**"A lighting guide embeds a live scene" is done on
`core/rendering.md`'s own "The look" section.** The same
`<div class="demo">` iframe onto a live shooter build (six torches, the
very "deliberate" lighting the ROADMAP writes about) is dropped right
under the text on tonemapping and post — not a made-up separate "about
lighting" guide, but the closest existing candidate.

Checked with a real site build, not only by reading code: `node
site/tool/build.mjs` builds 31 pages with no errors,
`dist/gallery/index.html` carries all four `<div class="demo">` blocks and
a working link to `dist/assets/samples/shooter.f3drun` (the file is really
copied there by the build), `dist/core/rendering/index.html` carries a
fifth `<div class="demo">`. This session did not run a full rebuild of
`site/tool/demos.sh` (four `flutter build web` runs, minutes of time) — the
mechanism itself is already proven by the fact that the four existing demo
pages stand on it; the gallery page simply reads the same output.

`dart run tool/structure.dart` from the root — 32/32 after syncing test
counts (drift from a concurrent session on `flutter3d_modeler`, only the
real delta applied). Not done: a full-fledged web editor (an architectural
boundary above this task's scope), a run recorder for the three genres
other than the shooter, "Strategy" as a full `NAV` section (strategy today
has a `demo.md` and a web build, but no `index.md`/`tutorial.md`/nav
section — a pre-existing gap, not created and not closed by this task,
only its already-built `/demo/strategy/` is used).

### net-04: diagnosing a desync

Closed 2026-09-12, with the same caveat as rp-05: the literal terminal
command `dart run flutter3d_net:diff a.f3drun b.f3drun` is not part of this
spike — checked empirically, not assumed, the same way: diffing two real
`.f3drun` files of a genre requires replaying each through that genre's own
real simulation, and `flutter3d_net` doesn't know a single genre (the same
reason `flutter3d_testing`'s `replayGolden` doesn't render on its own —
only the genre knows how to step its own simulation). A terminal command is
the same `flutter3d_build`/`ap-10` rp-05 is already waiting on.

**What's done — the mechanism, separate from the command.** `diffRuns` in
`flutter3d_net` (`lib/src/snapshot_divergence.dart`) is exactly what the
wording asks for: first a cheap `DigestTrace.divergenceFromHex` names the
first diverging checkpoint (the same answer net-01 already gives), and
only at that one step — and only there — a structural walk of the two full
JSON snapshots finds the first leaf where they diverge and names the path
to it (`entities.health.7`, `player.body.position` — whatever a genre
chose to nest its own state under; `diffRuns` itself doesn't know what an
entity is, it only recurses through `Map`/`List`). Nine tests in
`flutter3d_net/test/snapshot_divergence_test.dart` on bare JSON — a path
into nested maps, through lists, to a leaf; a length mismatch in a list
names the length itself; a repeated call after digests match is `null`;
and if the digests diverged but the full snapshots the calling code handed
over for comparison did not, `diffRuns` throws rather than silently lying
"no divergence."

**Proven on a real game, not only on bare JSON.**
`apps/flutter3d_demo_dungeon/test/desync_diff_test.dart` — two runs of the
same crypt: an honest one and one where the stick's own input flipped
direction from step 150 on (the same class of swap already checked in
net-01, only on a real genre rather than a toy). Two tests: two honest runs
never diverge; the flipped input gives a divergence no earlier than step
150, and the path really leads deep into the saved JSON rather than
stopping at the first key. A real finding along the way: the first thing
to diverge isn't the player's own position, but `actors.lastFocus[0]` —
who the nearest monster is looking at — because the flip changes who ended
up closer before the actual distance traveled changes; the test says this
plainly, rather than fitting the expectation to what seemed intuitive
beforehand.

### ai-00: `flutter3d_sim_mcp` — closed

Closed 2026-09-12, with a full scenario — clarified explicitly with the
owner before starting, because ai-00's own wording ran two of this
session's already-known limitations into each other at once: both the
genre (`flutter3d_game_shooter`) and the PNG frame (`flutter3d_cpu`) pull
in the Flutter SDK, while an stdio MCP server following
`flutter3d_editor_mcp`/`flutter3d_model_mcp`'s own pattern is `dart run`,
where Flutter is unavailable in principle. The owner chose the full
scenario through `flutter test` over a trimmed one (no monsters, no
frame).

**A real finding before a single line of code: `flutter test` breaks
stdio literally.** Checked with a two-line probe file before anything was
written: `stdout.writeln('READY')` inside a test doesn't reach the
terminal as `READY`, but as `Shell: READY` — the engine wraps everything a
test writes through its own log with that prefix. A protocol pinned to an
exact line format doesn't survive that. `stdin.readLineSync()` turned out
even worse — real input never reaches it at all, the call simply hangs.
Both checked with `Bash`, before the package itself was started — an
hour of development saved for five minutes of experiment.

**The fix: the same channel, a different transport.** `dart_mcp`'s
`stdioChannel` accepts any `Stream<List<int>>`/`StreamSink<List<int>>`
pair, not literally real stdio — meaning a `Socket` fits with not one
change to the protocol itself. `test/fixtures/sim_mcp_server.dart` (not
`_test.dart`, the same trick `timeline_target.dart` uses in rp-02) brings
up `ServerSocket.bind(loopback, 0)`, prints the port (through the same
`Shell: ` prefix — harmless for diagnostics) and wraps each connection in
a `SimMcpServer`. Works under `flutter test --reporter=silent` — the
ordinary reporter would also write into the same stdout the client reads
the port from.

**Six tools, all real code, nothing invented for the report.**
`open`/`step`/`snapshot`/`digest`/`writeRun`/`frame`. `snapshot` gives
positions, health, and alive-or-not for the player and every actor, by
name or by index. `digest` reads `DigestTrace` (a checkpoint every 25
steps) — the same thing net-04 now compares. `writeRun` writes a real
`.f3drun` (a `Demo` with `checkpoints`), openable in the editor like any
other run. `frame` is a picture of the room through the player's own eyes,
with no GPU, through `flutter3d_cpu`/`flutter3d_bridge`'s own
`LevelLoader` (the same `readAsset`/`readDocument` seam already letting
the editor read a level from disk rather than from a bundle).

**Staging — a fourth copy of the same function, honestly named, not
hidden.** `apps/flutter3d_demo_dungeon/lib/src/staging.dart`'s `stage()`
can't be imported by a package ("no package depends on an application"),
so `flutter3d_sim_mcp/lib/src/staging.dart` carries a trimmed copy (no
automap/breaches/hooks, none of which ai-00's tools read). Everything it
touches today is only `flutter3d_game_shooter` and `flutter3d_sim`,
nothing from the application — so moving `stage()` into
`flutter3d_game_shooter` itself would at once free the application, this
server, and a few more test files further into the tree from four copies
of one function; not done here deliberately — a separate task with its
own circle of touched code, not a side effect of ai-00.

**The instance plays blind, rather than peeking.** Three tests in
`test/sim_mcp_test.dart` (`@TestOn('vm')`), a real second process, a real
socket, a real `MCPClient` from `dart_mcp` — not a protocol mock: the six
tools match what `tools/list` offers; a step before `open` is a refusal,
not a crash; and the main one — an agent opens a real `crypt.json`, steps
forward 60 times, `snapshot` names the position and health in words,
`digest` names a checkpoint, `frame` really returns a PNG (checked by byte
signature, not only length), `writeRun` writes a `.f3drun` that
`Demo.fromJson` reads back, holding 60 steps of recorded tape and at
least one checkpoint — exactly ai-00's own acceptance: "an agent... clears
the crypt's first room by frames and words and hands back a run that
opens in the editor" (the actual opening in `apps/flutter3d_editor` wasn't
clicked — the same class of boundary as rp-02/net-02/net-03).

A new exemption entry was added to `tool/structure/repository.dart`'s
`genreRuleExempt`: `flutter3d_sim_mcp` deliberately, not by mistake, knows
the genre (a monster, a weapon, ammo) — the only tool package in this
session for which that's true, unlike `editor_mcp`/`model_mcp`.

### ai-01: playtesting in batches — closed

Closed 2026-09-12, with the same caveat as ai-00/rp-05/net-04: a literal
`dart run flutter3d:playtest` is again `flutter3d_build`/`ap-10`, which
doesn't exist; the mechanism itself lives in
`flutter3d_sim_mcp/lib/src/playtest.dart`, next to the staging code ai-00
already has.

`Playtest.run(levelPath, N)` — one `Isolate.run` per run, sharing nothing,
no queue: N independent worlds of one level, honestly in parallel, not an
imitation of parallelism through `async`/`await` in one isolate. The
random policy (`_RandomDriver`) holds a direction and a look for dozens of
steps in a row, rather than flipping them every frame — the same trick
every synthetic driver in this session uses, because noise averages to
standing still, and a level deserves to actually be walked into. Three run
outcomes are read from what `GameSimulation.state` already gives
(`died`/`exited`), and a fourth — `stuck` — fires if the position hasn't
moved `stuckStride` meters in `stuckAfter` steps, its own separate
heuristic, because the step itself knows nothing like it.
`Playtest.heatmap()` — a density map by cell plus a list of death points
and an outcome summary, exactly the JSON shape `ai-02` will ask for.

Three tests in `flutter3d_sim_mcp/test/playtest_test.dart` on a real
crypt: eight runs, each reaching an outcome, the heatmap accounting for
exactly eight; the same seed gives the same run twice (including the full
position list, not only its length); and — an honest, not fitted, check —
that `stuck` actually fires at least once across several attempts, rather
than merely existing in theory as an enum value.

Another exemption entry was added — this time to `boundaryEnumExempt`, not
`genreRuleExempt`: `PlaytestOutcome` is the same class of enum already
exempted for `GameState`/`RunOutcome` — a closed set the `Playtest` loop
itself controls, not content that has anywhere to grow.

Not done: the terminal command (`ap-10`), and writing the heatmap to a
file on disk as a separate call — `jsonEncode(Playtest.heatmap(...))`
already gives a ready structure, `File(...).writeAsString` on the calling
side is one line, which `ai-02` writes alongside the report layer itself.

### ai-02: a heatmap in the editor — closed

Closed 2026-09-12. `flutter3d_editor` stays genre-agnostic by design — the
editor doesn't know what a monster or a weapon is — so the report layer
in `apps/flutter3d_editor/lib/src/playtest_report.dart` (`HeatmapCell`,
`DeathPoint`, `PlaytestReport.fromJson`) reads the bare JSON of ai-01's own
`Playtest.heatmap()` with no dependency on `flutter3d_sim_mcp`: a heatmap
is cells, death points and an outcome counter, none of which names a
single genre.

The drawing is `playtest_heatmap_view.dart`. `HeatmapLayout` is pure
arithmetic translating world coordinates to screen ones (fitting the
level's own footprint into whatever size `LayoutBuilder` hands it, with
margins), deliberately its own class separate from the widget: arithmetic
is cheaper to check directly than through `WidgetTester`'s own hit
testing, which only confirms drawing and hit testing agree with each
other, not that either is actually correct. `PlaytestHeatmapView` is a
`CustomPaint` over it: a cell's density as a color from transparent to
orange, death points as red circles with a white outline, a tap counted
through `HeatmapLayout.hitTest`. `PlaytestReportScreen` opens the JSON
through `file_selector` (the same package `editor_chooser.dart` and the
rest of the editor already use), and tapping a death point shows a dialog
with its seed, step and coordinates.

An honest boundary: the task's own literal "opens the timeline at this
step" isn't done here and can't be, in its current shape — first, the
editor can't step any genre's own simulation (genre-agnostic, the same
decision `rp-02` made), and second, `Playtest` doesn't yet write a
`.f3drun`/`InputTape` for a run, only sparse `(x, z)` points — there's
nothing to scrub even if a genre host existed. The dialog says this
plainly, rather than pretending scrubbing happened.

Five tests in `playtest_heatmap_view_test.dart` on `HeatmapLayout` and
`PlaytestHeatmapView` (a death point is found exactly where it was placed;
a tap missing every point finds nothing; an empty report still gives a
usable layout; a tap on a marker fires the callback; a tap on empty ground
doesn't) and three in `playtest_report_screen_test.dart` (with no report,
the text reads "No report open," not an empty canvas; a handed-in report
shows its own run count and outcomes; a tap on a death point opens a
dialog with the right seed and step). The entry button is `Icons.grain`
next to the already-existing `Icons.podcasts` in `main.dart`, the same
`IconButton` → `Navigator.push` pattern.

Not done: writing a `.f3drun` per run inside `Playtest` (needed for real
scrubbing), and the literal terminal command itself — the same reason as
ai-00/ai-01 (`ap-10`).

### par-02: the diagnostic MCP — closed, scope narrowed by the actual findings

Closed 2026-09-12. A new package, `flutter3d_render_mcp`, alongside
`flutter3d_editor_mcp`/`flutter3d_model_mcp`, not alongside
`flutter3d_sim_mcp`: frame diagnostics know nothing about a genre, and
`open` takes an `EntityRegistry` as a parameter rather than importing (as
ai-00 does) one genre's own vocabulary — the one thing worth knowing about
that is: a level whose entities an empty registry doesn't recognize
doesn't validate, and that's the same honest boundary as everywhere else
in this session, not an oversight. A frame with no GPU — the same trick as
ai-00 (`flutter3d_cpu`, a socket instead of stdio, because `flutter test`
wraps `stdout` in `Shell: `).

**A real finding before the code: `readPixels` already hides exactly what
diagnostics needs.** `CpuTexture.pixels` is a `Float32List` with no clamp
at all; `CpuDevice.readPixels` converts it to 8-bit through
`pixels[i].clamp(0.0, 1.0) * 255`, and `double.nan.clamp(0.0, 1.0)` on this
SDK answers `1.0` — checked with a two-line `dart run` probe, not assumed.
A NaN a broken shader wrote reaches an ordinary picture as an ordinary
white pixel, exactly what a NaN scan can't catch through the existing
public API. `CpuDevice.readHdrPixels` was added — the same `Float32List`,
with no clamp and no conversion — with its own test
(`flutter3d/test/hdr_readback_test.dart`) pinning down both facts at once:
a depth of ten meters survives `readHdrPixels` and drowns in `readPixels`
(`255`, meaning `1.0`).

**Debug views already exist in `RenderSettings`, not invented here.**
`showSurfaceBuffer` (plus `surfaceBuffer`, which turns the recording on)
composites the normal/depth buffer directly into the frame — R/G an
octahedral normal, B roughness, A view-space depth in meters
(`packages/flutter3d_shaders/shaders/lib/color.glsl`'s
`WriteSurfaceGeometry`). `showShadowMap`/`showStaticShadowMap` do the same
for the two cubic point-shadow atlases. `DiagnosticView` (an enum,
`lit`/`normals`/`shadowMap`/`staticShadowMap`) simply names these four
switches; a `boundaryEnumExempt` entry was added, the same shape as
`PlaytestOutcome`'s: a fifth value would need a fifth setting on
`RenderSettings`, which doesn't exist today.

**The acceptance criterion was checked empirically, and the answer wasn't
what the wording suggested.** The ROADMAP's own "a broken normal map"
doesn't say exactly what breaks it — the intuitive guess (a solid,
medium-gray normal map, `(128,128,128)`, decoding into a degenerate
tangent vector, with `normalize()` giving a NaN) didn't hold up: 8-bit
quantization doesn't land exactly on `0.5`, the decoded vector comes out
small but not zero, and it renders merely a bit dimmer — checked with a
direct test render before a single diagnostic tool was written. A solid
**black** normal map (`(0,0,0)`, what a level is really wrapped in if its
texture failed to load and the placeholder is black, not a neutral blue
`(128,128,255)`) decodes into `(-1,-1,-1)` — a normal pointing into the
surface, which drives `n_dot_l` negative for almost every light and makes
direct lighting vanish. The same material with a neutral map gives `235`
on the 8-bit channel, with the broken one — `40`: the difference is
visible with no interpretation needed. This is a real,
guarded-PBR-compatible bug (`D_GGX`/`V_SmithGGXCorrelated` in `pbr.frag`
are guarded by `max(x, 1e-6)` against any honest division by zero that
would give a NaN) — not invented for the report.

**Tools**: `open`, `frame` (view `lit`/`normals`/`shadowMap`/
`staticShadowMap`, from a given eye point and look direction), `pixel`
(raw, unclamped RGBA plus decoded normal/roughness/depth for the `normals`
view; for any view, names the source pass through `describePass`),
`passes` (what actually ran in this frame — name, activity, time, from
`FrameResult.passes`, with no recomputation), `scanNaN` (the first
non-finite pixel in the last frame, if any). `pixel` for the `lit` view
always names `"scene"` as the sole pass computing material lighting —
exactly the "pass name" the acceptance criterion asks for, handed back as
a fact, not a guessed string.

A test in `test/render_mcp_test.dart` — a real second process, a real
socket, a real `MCPClient`: a level with two walls under one light,
differing only in their normal maps; `frame` draws both; a pixel-grid scan
through `pixel` finds the brightest point in each half of the frame
(rather than assuming projected coordinates in advance); the broken wall
reads noticeably darker than the intact one; `passes` confirms `"scene"`
was really active in this frame; and `pixel`'s answer at a dark pixel names
that same `"scene"` that `passes` does — this is "an agent names the pass"
from the acceptance criterion, checked as data, not taken on faith as
text.

Not done, honestly and for named reasons: the literal terminal command
(`ap-10`, the same class of limitation); an arbitrary frame-graph node's
own output as a texture (only name/activity/time — `FrameResult` doesn't
store every node's own texture separately); overdraw (the software
rasterizer doesn't count fragment invocations separately from the final
color); shadow cascades individually (there are only two whole atlases,
no per-cascade breakdown); a snapshot of an already-open editor's own
viewport/window and connecting to it over loopback (the same class of
boundary as rp-02/net-02/net-03/ai-00: a live desktop editor can't be
brought up in this environment). The `normals` view also can't see this
exact bug — `WriteSurfaceGeometry` encodes the geometric varying normal
(`v_normal`), not `s.n` after the normal map is applied, so the normals
debug view stays "clean" exactly when the map itself is broken; this isn't
a tool shortcoming, but an honest fact about the surface-buffer's own
architecture, separately recorded in `DiagnosticView.normals`'s own doc.

### par-03: skills for the engine's own users — closed

Closed 2026-09-12, with the same caveat as ai-00/ai-01/ai-02/rp-05/net-04:
a literal `dart run flutter3d:skills` is again `flutter3d_build`/`ap-10`,
which doesn't exist (checked — there's no package with that name anywhere
in the tree). The mechanism and the content itself live in the new
`tool/skills` (a flat Dart package under `tool/`, not under `packages/`,
the same trick and for the same reason `tool/convert_asset`'s own pubspec
already gives: a package under `packages/` is checked against
ARCHITECTURE.md's publishing order, and this one doesn't go out at all).

An important wording clarification: these are not the skills already
sitting in `packages/*/skills/*/SKILL.md` — those are written for people
developing the engine itself. par-03 writes skills for people **building a
game on the engine** — into the user's own project, not into this
repository. `writeEngineUserSkills`
(`tool/skills/lib/src/skills_writer.dart`) puts them into
`<project>/.claude/skills/<slug>/SKILL.md`, the same path and the same
frontmatter (`name`/`description`) already adopted across the whole tree.

Four SKILL.md files, each carrying real facts drawn from the code, not
generalities: idioms and quiet traps (`LodGroup.select()` doesn't call
itself — before the first call, and on every skip, the most detailed level
draws with no error at all; LOD auto-assembly from `ModelLod` silently
disables itself for a node with several materials;
`RenderSettings.copyWith` once lost seven fields at once, exactly what
`render_settings_test.dart` now catches; wireframe is silently declined on
two of three backends — check `FrameResult.wireframeDeclined`, not the
picture; anisotropy has no effect on a bilinear sampler); light and
post-processing (`tonemap`/`bloom` are on by default, `sky`/`reflections`/
`ambientOcclusion`/`xray` are off; the sky's own color is linear and goes
through exposure and the tone curve, unlike `clearColor`, which is decoded
from sRGB; turning ambient occlusion on silently turns MSAA off for the
whole frame; `thickness` in `ReflectionSettings` is meters, not window
depth; `RenderSettings.forStereo()` is the one correct way to turn off
three effects that compute wrong on a stereo pair); performance (a screen
fraction, not distance, drives `LodGroup.select`; anisotropy is clamped by
the device's own `maxAnisotropy`; `BloomSettings.levels` is both radius
and cost, not `intensity`); runs and networking (`Demo`/`.f3drun` requires
`levelHash`, `buildStamp` and `checkpoints`, not optionally;
`GameRandom.state` is the one thing that needs saving for the same future
rolls after loading; `NetSession`'s three parameters —
`inputDelay`/`maxRollbackFrames`/`redundancy` — trade off against each
other rather than standing independent, and `droppedCorrections` is the
signal that the window is too small for the connection; `onSettled` is the
one correct moment to take a digest checkpoint, because a digest taken
earlier is a digest of a guess not yet confirmed).

Idempotency — the task's own acceptance ("running it again is an empty
diff") — is guaranteed by construction: the content is a compile-time
constant, the write is unconditional, meaning the result is byte-identical
on every call; checked both by a test (comparing bytes before/after a
second call on a temp directory) and by hand with the real CLI (`dart run
tool/skills/bin/skills.dart`, `md5sum` before and after match). A separate
test confirms the write doesn't touch someone else's already-existing
`.claude/skills/my-own-thing/SKILL.md` in the same project.

Thirteen tests in `tool/skills/test/skills_writer_test.dart`: the write
itself (all four files present, with the expected frontmatter);
idempotency; other skills left untouched; and — more important than the
rest — a group of tests per SKILL.md that grep the engine's own **real
sources** (`lod_group.dart`, `render_settings.dart`, `demo.dart`,
`net_session.dart`) for exactly the fields and methods the content names
by name — catching future API drift, not just today's snapshot, the same
trick net-04 used to find `actors.lastFocus[0]`, rather than simply
trusting text written in advance.

Not done: the literal `dart run flutter3d:skills` itself (`ap-10`), and
"an agent gets through the quickstart with none of the mistakes the
skills describe" — the acceptance's second half — wasn't run as a
separate scenario with a fresh agent: each trap was instead checked
against the real behavior of the code it describes, which is cheaper and
no less honest, but not the same thing as a live run.

### edu-00: the interactive's specification — the document is ready, no review has happened

Written 2026-09-12, as a separate file
[doc/edu-00-interactive-format.md](edu-00-interactive-format.md) — an S
task that really is, at heart, one document, but not inside
`tooling-plan.md`, so the format lives where
`doc/lesson-scenarios-plan.md` already references it.

The decision: there is no second scene format — an interactive is just
five more entity types (`edu_sequence`, `edu_step`, `edu_annotation`,
`edu_clip_plane`, `edu_data_source`) in the same `Level` document already
read by the game, the editor and the MCP servers. Found and checked, not
assumed: `flutter3d_editor_core`'s `vocabularyOf` keeps an open list of
entity types (`OpenKind`) — meaning a document with new `edu_*` types
opens, saves and passes editor validation already today, with not one line
of edit to the editor itself.

**A real finding along the way, not only at net-04.** The document's first
draft example nested a step's fields under a `"properties": {...}}` key,
the way the tooling plan's own captions might have suggested. A run
through a real `Level.fromJson` + `vocabularyOf` (a temporary test in
`flutter3d_editor_core`, not over a mock) showed: `EntityDef` doesn't know
a `properties` key at all — everything outside `type`/`at`/`yaw`/`name`
itself becomes the property bag, so a nested `"properties"` lands as one
property carrying that whole name, not as fields inside it. The format in
the document was rewritten flat, the same shape any existing level entity
carries (`door` with `size`/`travel`/`speed` directly alongside
`type`/`at`), and the example in the document's own §11 was re-checked with
the same run again — six entities, five new types, all pass
`vocabularyOf(...).knows(...)`, and `toJson()` → `fromJson()` preserves
`offsets`/`steps`/`widget`/`check.attempts` with no loss.

Not done, and this session honestly cannot do it: edu-00's own acceptance
— "the document has been read by two people with different backgrounds
(an instructor, an engineer), their notes folded in" — is a live-review
step, not something an agent checks against itself. The document is ready
for that reading; there is no confirmation here that it happened. `edu-00`
therefore isn't marked "closed" in its own heading — it's marked with what
is actually true.

### edu-01: authoring in the editor — closed, disassembly as separate entities, not a node inside one

The panel was written on 2026-09-12; the table row was caught and narrowed
on 2026-09-13, then closed the same day, after checking which path
disassembly actually needs for real content. The real finding that shaped
the whole task's scope:
**not one new `EditorCommand` was needed.** Every `edu_*` type from
`edu-00` is an ordinary `EntityDef` with a flat property bag, and
`flutter3d_editor_core`'s `Place`/`SetField`/`Delete`/`Turn` already know
how to place any entity, write into any of its keys, delete it and rotate
it — `edu_step`, `edu_annotation`, `edu_clip_plane` are no more special to
these commands than `door` or `monster` are. The task's own wording ("all
through commands, meaning through MCP too") turned out to already be
satisfied by ten commands that existed before this task started — not
because the task got trimmed, but because the open type vocabulary
(`edu-00` §1) removed the need for a second set.

**The step panel selects; `EditorInspector` edits.** A second finding, from
`editor_inspector.dart`'s own doc comment: it already draws one row per key
for any entity, "including a field this build has never seen" — meaning
`caption`/`offsets`/`widget`/`attachTo` already get an editable row for
free the moment a step is selected. A second, dedicated inspector for
`edu_*` keys would repeat exactly what that doc comment already refused: "a
hidden field this build has never seen." `StepPanel`
(`apps/flutter3d_editor/lib/src/step_panel.dart`) therefore doesn't edit
fields at all — it adds a step, reorders it within the `edu_sequence.steps`
list, deletes it, drops an annotation or a clipping plane, and at the end
of each action selects the resulting entity (`editing.select`) so the
inspector immediately shows its fields.

**"The cross-section's gizmo" is the same gizmo any entity has.**
`edu_clip_plane` carries `yaw`, like everything else in this format
(`edu-00` §5 already decided this for a step's own camera) — it can be
rotated with the same arrows/`,`/`.` that already rotate any selected
entity in `main.dart`, with not one line of new code for interactive
input. A plane is created and then rotated — not dragged by its normal
through a dedicated 3D handle, which this session didn't need to build.

**Drag-to-disassemble closed via separate entities, not a node inside one
model** — found on 2026-09-13, along with why that's the right choice, not
a workaround for something unfinished. `ls-e-00`, the first real content
on this format, disassembles an engine as four separate `'part'` entities
(`engine-block`/`valve-cover`/`air-filter`/`spark-plug`), each with its own
`EntityDef.position` — and a separate entity is already moved today by an
ordinary `AxisDrag`/`MoveBy`, the same gizmo that moves a door or a
monster, with not one new line. `mergedOffsets(step, nodePath, delta)`
(`packages/flutter3d_editor_core/lib/src/lesson_authoring.dart`) is the
same trick `HeatmapLayout` (ai-02) and `bindingsInLevel` (edu-05) already
chose for arithmetic kept separate from the widget — but it's computed for
a DIFFERENT case: one named node (`valve_cover`) inside ONE model with
several named parts, rather than several entities side by side. Neither
`engine-body` nor `valve_cover` exists in the tree — it's an example from
a doc comment and a test, not from actual content; nobody calls the
function today, because no real lesson has chosen the scenario it was
computed for.

Picking exactly that kind of internal node is technically possible
already, checked rather than assumed: `renderer.pickPixel` already returns
a real named `MeshNode` — `scene_dressing.dart`'s `dressGizmos` calls
`asset.instantiate()` for any entity with a model and puts `instance.root`
into `SceneDressing.owners`, so a click on a node like `valve_cover` inside
a model with many named parts is physically distinguishable by
`main.dart`'s `_handleUnder` (which today hands back the owner as a whole,
not the node itself, but the node was in its hand). Building picking, a
gizmo, and a second write path (`SetField('offsets', ...)` instead of
`MoveBy`) for a data shape no lesson has chosen would mean writing an
interface with no scenario — an owner decision, made after checking
confirmed this, not a guess that it would be faster. `movedStep` reorders
the name list for reordering a step, `freshName` explains why `Place`'s own
copying of the last entity of the same type doesn't leave two steps with
one name (`Editing.place` copies the last entity of a type's own
properties, including `name` — a finding, not a guess; without
`freshName`, a second `place` of an `edu_step` would give the step the
first one's name, until `SetField('name', ...)` overwrote it).

**Proven twice — as an `Editing` object and as a real MCP session.**
`packages/flutter3d_editor_core/test/lesson_authoring_test.dart` (14
tests: pure arithmetic for `mergedOffsets`/`movedStep`/`freshName`/
`indexOfNamed`/`orderedSteps`, and one integration test — a five-step
engine teardown assembled entirely through calls to
`Place`/`SetField`/`Turn().apply(editing)`, with not one hand-written JSON
object, read back through `Level.fromJson`). The same thing again, one
layer further out —
`packages/flutter3d_editor_mcp/test/lesson_authoring_mcp_test.dart`: a
real `MCPClient`, a real socket, the same five-step scenario through
`place`/`setField`/`select`/`turn` — existing tools, not one new one
registered for `edu_step`. Plus 9 widget tests in
`apps/flutter3d_editor/test/step_panel_test.dart` on the panel itself (an
empty lesson says so; adding, selecting, reordering, reorder boundaries
(the first doesn't move up, the last doesn't move down), deleting stays in
sync between the list and the entities, an annotation binds by name, a
cross-section is created and selected) — 24 new tests in total, all green
together with the full suite of all three touched packages.

Not done, and deliberately: node-level drag under `mergedOffsets` —
`_handleUnder` doesn't pass the node's name out, `offsets` has no gizmo or
gesture of its own, and `editor_inspector.dart`'s own generic inspector
still draws a Map as `_ReadOnly` by its own "no special case per field"
principle — but that's no longer this row's own gap, since no lesson has
chosen the data shape it would edit. Beyond that, as before: "gets a link"
— publishing a lesson (a URL, hosting) has no mechanism in the tree, the
same unbuilt infrastructure as `tpl-02`'s; a full 3D handle for the
cross-section (replaced by rotating an already-existing entity); the
editor's own web build wasn't run live in a browser — only `flutter test`
on the VM, enough for the panel's own logic and commands, but not the same
thing as running in Chrome.

### edu-05: live data in a scene — closed

Closed 2026-09-12, with the same caveat as ai-00/ai-01/par-02: the literal
acceptance ("a machine from the `tpl-04` template") is unreachable —
`tpl-04` doesn't exist (waits on `wg-01`+`edu-01`; `edu-01` hadn't started
yet). Built and proven is the mechanism, on a real, honestly synthetic
scene, not an imitation of the template's own screen.

**The source is `sampler`, not a pretend MQTT.** `EduDataSource`
(`flutter3d_sim/lib/src/level/data_source.dart`) is an interface with one
method, `sample(step)`; `SamplerDataSource` is a deterministic function of
the step, the one implementation this session can honestly check with no
broker in CI. `mqtt`/`websocket` are adapters to the same interface that
edu-05's own code doesn't write — not out of laziness, but because a real
MQTT broker in a CI test is a separate infrastructure task, not a line of
this spike. `DataSourceRegistry` holds sources by name and can `replace()`
— swap a source under the same name, with no history before that moment,
because nothing in the registry is stored before that moment, only read.

**The binding — edu-00 §9's flat format, checked on a real
`Level.fromJson`.** `resolveBindings(step, atStep, registry)` reads
`edu_step.bindings` (`source`/`path`/`target`), finds the source by name,
pulls a value by a dotted path one level deeper than
`EntityDef.number`/`.vector` already read their own properties
(`sensors.spindle.rpm`). On the editor side —
`bindingsInLevel(level)` in `flutter3d_editor_core`
(`lib/src/binding_lookup.dart`): which entity property is currently bound,
to which source and which step — what the inspector needs to know before
deciding to draw a field as `_ReadOnly` rather than editable. The decision
itself isn't wired in: `editor_inspector.dart`'s own field dispatcher is
untouched, an honestly named remainder, not a hidden one.

**History as input — a new, additive channel next to `InputTape`, not a
second, incompatible way of recording a tape.** `DataSourceTrace`
(`flutter3d_sim/lib/src/save/data_source_trace.dart`) — the same style as
`DigestTrace`: a dense "step → values" recording, `toJson`/`fromJson`,
`branchAt(step, throughStep, continuation)` — a new object with the same
prefix and a different continuation, leaving the source untouched. `Demo`
got an optional `dataSources` field (a fifth optional field after
`platform`/`recordedBy` from rp-01, the same way — an old `.f3drun` with
no such key still reads as before).

**Branching is proven on top of rp-02's own already-checked mechanism, not
alongside it.** `run_timeline_data_source_test.dart` in
`flutter3d_session`: three hundred steps of a real recording
(`RewindBuffer`/`RunTimeline`, the same `_Toy` class as
`run_timeline_test.dart`, with a `temperature` field added, read from
`DataSourceRegistry` every step and written into `DataSourceTrace`) →
`timeline.preview(3.0)` and `timeline.releaseAt(point)` — literally the
same call already proven in rp-02 to land wherever an independent replay
would land — carries the twin's own live state to the found step →
the source is swapped AFTER this, not before → thirty steps of real
continued play with the swapped source write a separate `DataSourceTrace`.
Checked: the live `toy.temperature` after release comes from the swap, not
from the original formula; the branch matches the original up to the break
point and diverges after it; **the original `trace` itself, serialized to
JSON before and after the whole procedure, is byte for byte the same** —
"no rewriting history," literally, not merely as a claim.

Eleven tests in `flutter3d_sim/test/data_source_test.dart`
(`resolveBindings` on a real, flat level — no `properties` wrapper,
edu-00 §2's own finding; `DataSourceTrace` as a forward-only recording,
round-tripped, `branchAt`; `Demo.dataSources` optional both ways), four in
`flutter3d_editor_core/test/binding_lookup_test.dart`, one integration
test in `flutter3d_session` — sixteen new tests in total, all passing
together with the full suite of all three touched packages.

Not done: the literal `tpl-04` (the "machine"); real MQTT/WebSocket
adapters over `EduDataSource` (the interface exists, only `sampler` is
implemented); wiring `bindingsInLevel` into `editor_inspector.dart`'s
actual field-widget choice — today it's a separate, ready-to-use function,
not something the inspector actually calls.

### edu-06: stereo for a classroom — closed

Closed 2026-09-12. The same document `edu-01`'s own step panel assembles
(`edu_sequence`/`edu_step`), played back through `StereoRig` instead of
edited through it — not a second way to read a step: `orderedSteps`
(`edu-01`, `lesson_authoring.dart`) already resolves `edu_sequence.steps`
into the entities themselves; this item only says what a step means for
the rig.

`packages/flutter3d_stereo/lib/src/lesson_player.dart` — `applyLessonStep`
moves the rig's own `stage` to a step's `at`/`yaw` and shows/hides named
scene nodes by a step's own `visible`/`hidden` lists, touching nothing a
step doesn't name (the same "every step carries the full state of what it
touches" convention `edu-00` §5 already adopted). `LessonPlayer` —
`next`/`previous`, both **clamped, not wrapped**: a student pressing next
past the last step should see the last step held, not suddenly the first.
`lesson_stereo_view.dart` — `LessonStereoView`, a `StereoSurface` with two
buttons over it; a button, not a keyboard and not scrolling — `wg-01`'s own
honest finding that neither reaches a widget inside `WidgetSurface`
doesn't directly apply here (the buttons are ordinary `IconButton`s over
the stereo surface, not inside it), but the choice of a button over a
gesture is the same one: a phone in a cardboard headset has no keyboard at
all.

A new dependency: `flutter3d_stereo` now pulls in `flutter3d_sim`
directly, the same path `flutter3d_editor_core` already chose — flat Dart,
no genre, no Flutter; pulling it in through `flutter3d_game` would have
been an extra layer for one class (`EntityDef`).

Eight tests in `lesson_player_test.dart` — pure arithmetic with no
rendering, the same trick `stereo_rig_test.dart` already chose (world eye
positions, not a picture): moving the stand to a step's position and
angle; showing/hiding by name with no effect on what wasn't mentioned;
clamped player boundaries; an empty lesson doesn't throw; a button moves
both eyes together with the stand by exactly the distance the stand
moved — and alongside it, a real finding, not a fitted one: the same move
with a simultaneous `yaw` change does NOT move the eyes by the same
distance, because turning the head also rotates the offset between the
eyes — the test says this plainly, instead of widening the tolerance until
it matched. Two tests in `lesson_stereo_view_test.dart` — a real
`CpuDevice` (no GPU, the same trick `wg-01`'s own tests use), tapping
"Next" really hides a node and moves the `stage`; the "Previous" button is
really disabled on the first step (`onPressed == null`), not merely
supposed to be.

An honest boundary: there's no real phone with Cardboard goggles in this
environment — the rig, the document and the button are proven, not the
glue and the lens glass. The five-step ladder from the task's own
wording — the engine teardown itself — isn't built as a separate asset
with a real 3D engine model: the tests use synthetic three-step scenes
with named empty nodes (`SceneNode`), because the task is to prove the
lesson-playback mechanism, not to create the specific teardown content
(the same split `doc/lesson-scenarios-plan.md` already draws between
`tooling-plan.md` (the format and the code) and its own content plan
(`ls-x-00`, which is exactly the one meant to fill this scene with a real
model, when its turn comes).

### edu-02: a public page and an embed — a flat player is written, the service is deployed on lessons.pleion.dev

Written 2026-09-12, after `edu-06` and on its own subdomain,
`lessons.pleion.dev`, rather than `models.pleion.dev`, as the task's
original wording named — by Dmitrii's own decision: its own service, its
own nginx, its own cloudflared tunnel, isolated from the model catalog.

**A real finding that set the task's scope.** The wording names only the
cloud wrapper, but research before starting found: a step player for a
flat (non-VR) screen didn't exist at all — only `flutter3d_stereo`'s
`applyLessonStep`/`LessonPlayer`, written for `StereoRig`/Cardboard, and
`tpl-04`'s `ViewerTourController`, which only cycles a caption's text,
touching neither the camera nor visibility. `edu-02` therefore isn't just
a deploy — a real flat player was written first.

**`packages/flutter3d_bridge/lib/src/lesson_player.dart`** —
`applyLessonStepToCamera(SceneNode camera, EntityDef step, {nodes})` and
`LessonPlayer` (`steps`/`index`/`next`/`previous`, clamped, not wrapped),
the same shape as the stereo version, minus the notion of a "rig": in the
flat case the camera is its own stand, a `SceneNode` the calling code
drives directly. The location wasn't arbitrary — the stereo version's own
doc comment already names `flutter3d_bridge` as the place "where
`EntityDef` already meets `SceneNode`." Five new tests, 74/74 of the whole
package green.

**`apps/flutter3d_lesson_viewer`** — a new application, a read-only
showcase: not an extension of `flutter3d_template_app` (that one is a
project's own seed with a walking body) and not `flutter3d_editor`
(authoring, with no `web` target at all). The scene's camera is a
`CameraNode`, which itself turned out to be a `SceneNode`, so
`flutter3d_bridge`'s `LessonPlayer` fit with no signature change;
`LevelLoader().build()` doesn't ask for a `CollisionWorld` when there's no
walking body, so the application is simpler than `template_app`. The level
is chosen with `?level=` at runtime (with no same-origin check, unlike
`flutter3d_modeler`'s own `?model=` — here `rootBundle.loadString` only
reads what's already bundled into the build itself, not a foreign URL) or
`--dart-define=level=` for local development. The default content is
`assets/levels/tour.json`, the same three-camera-view tour `tpl-04`'s own
`viewer.json` already proved. The document also carries a fourth entity,
`quiz-steps` with a `check`, added after the first deploy — but not in the
shipped `edu_sequence.steps` sequence (rolled back, see below).

Honestly not wired in: a `widget_surface "view-caption"` in the content
isn't resolved by the widget registry (`WidgetSurfaceVisuals.add()` on an
unknown name writes an `Issue` and doesn't draw, rather than throwing) — a
step's own caption shows as 2D text over the scene rather than through
`WidgetSurface` itself; a working, tested path, but not the one `edu-00`
§7 describes.

**Added after the first deploy, by Dmitrii's own direct request: the
camera between steps is a carousel, not a statue.** `edu-00` gives a step
no orbit target, only `at`/`yaw`, but a showcase that simply holds a
step's own canonical view motionless is a slideshow, not something you can
turn. The fix —
`packages/flutter3d/lib/src/engine/scene/orbit_controller.dart`'s
`OrbitController` (the same one already letting `flutter3d_modeler` be
turned by mouse/touch), with its orbit target at the world origin — the
same convention the finished tour's own pedestal already stands on
(`[0, 0.5, 0]`). A step still places the camera exactly where `edu-00`
says (`applyLessonStepToCamera` is untouched); after that, the orbit's own
numbers (`distance`/`yaw`/`pitch`) are recomputed from the resulting
position, so the gesture continues from exactly there, not from stale
numbers. `lib/src/orbit_cubit.dart` — `OrbitCubit`, so the camera is part
of the same Cubit style `LessonCubit` already uses in `main.dart`, rather
than the widget tree's only `setState` field; `Cubit.emit` doesn't notice
a mutation of the same object, so every call emits a fresh `OrbitPose`
snapshot of the controller's own numbers, rather than the controller
itself a second time.

**Three real bugs, found only by a live run in the browser, not by
tests.** Not one was caught by `flutter test` — all three are visible only
on a running `flutter run -d chrome`, and each was found by Dmitrii's own
direct observation, not by logs:
1. Step `view-front` in `tour.json` had `yaw: 3.1416` — a camera at
   `z=+3` looked toward `+Z`, meaning away from the pedestal, not at it.
   The formula `forward = (-sin(yaw), 0, -cos(yaw))` (confirmed in
   `flutter3d_audio/lib/src/listener.dart` and `actor_visuals.dart`) —
   the first step's camera looked at an empty wall. All three camera
   positions in `tour.json` were recomputed from this formula.
2. A gesture really moved the `OrbitController` (confirmed by a widget
   test checking the camera object itself), but the picture on screen
   didn't change: `SceneSurface` only calls `renderer.render` from inside
   its own `build()`
   (`packages/flutter3d_session/lib/src/scene_surface.dart`), and mutating
   a scene node on its own doesn't mark the widget dirty. With no
   `setState`/`Cubit.emit` after the gesture, the camera moved but no
   redraw followed — a test didn't catch this, because it read
   `camera.readWorldPosition()` directly, not whether the frame redrew.
3. A trackpad pinch on macOS in the browser arrives not through a
   `PointerPanZoomUpdateEvent` (which `flutter3d_modeler`'s own
   `_panZoom` uses for the same trackpad) and not through a
   `PointerScrollEvent`, but as a separate `PointerScaleEvent` — a
   web-specific signal found only by logging a real gesture (over a
   hundred events from one pinch). `PointerScaleEvent.scale` is a step
   since the last event, not a running sum, unlike
   `ScaleUpdateDetails.scale`/`PointerPanZoomUpdateEvent.scale`.

**Not checked on Windows/Linux.** Rotating with the mouse
(`ScaleUpdateDetails`, `pointerCount=1`) and zooming with the wheel
(`PointerScrollEvent`) are ordinary Flutter events, identical everywhere.
But `PointerScaleEvent` (a trackpad pinch) was found empirically only on
macOS+Chrome — per the documentation this is Chromium's own translation
of a trackpad gesture into `wheel`+`ctrlKey`, which shouldn't be
macOS-specific, but wasn't checked live on Windows/Linux. Worse: across
every run on this machine, `PointerPanZoomUpdateEvent` never fired even
once — possibly dead code, left in by analogy with `flutter3d_modeler`,
with no confirmation it fires anywhere at all. This session's own lesson
is: don't trust confidence in someone else's (even tested) code behavior
without checking it yourself; the same caution applies here to
Windows/Linux until they're actually checked.

8/8 application tests (including one on `PointerScaleEvent`, simulated
through `GestureBinding.instance.handlePointerEvent` — a test that would
have caught exactly this bug immediately, had it been written before the
finding), `flutter analyze` clean.

**`cloud/lessons/server`** — a heavily trimmed version of `cloud/server`:
no accounts, no Postgres, no uploads, no jaspr (pages are plain Dart
functions returning HTML strings; no forms, no sessions, no reactivity
that would justify a component library). The lesson list is
`lessons_registry.dart`, data in code, not a file or a database: setting
up storage before a single real lesson has been uploaded is answering a
question nobody asked. Routes: `/health`, `.mount('/app/', ...)` under the
`flutter3d_lesson_viewer` web build, `GET /l/<slug>` (a public page with an
iframe and an embed snippet), `GET /e/<slug>` (a bare embed page — what's
actually placed in someone else's `<iframe src=...>`).

**The key divergence from `cloud/server`, the reason the whole service is
separate rather than a route in the existing one.** `cloud/server`'s
`_securityHeaders()` sets `frame-ancestors 'none'`/`X-Frame-Options: DENY`
on every HTML page — deliberately, so the model catalog can't be embedded
in someone else's page. `/e/<slug>` here must allow cross-site embedding —
edu-02's own acceptance ("embedded in a Stepik page and in a GitHub
README") requires exactly this. The fix is not "a permissive header
value" but its **absence**: `X-Frame-Options` and `content-security-policy`
aren't sent at all on `/e/`, because absence itself means "embedding is
allowed," while a permissive value is one future edit away from silently
becoming a forbidding one. The test says this plainly: `/e/<slug>` is
checked for the **absence** of both headers, not for a specific value.
`/l/<slug>` keeps a protective `X-Frame-Options: SAMEORIGIN` — nobody
asked to embed it. 9/9 service tests, `dart analyze` clean.

**A bug found after the first deploy, not before it.** A bare
`https://lessons.pleion.dev/` fell into `notFoundHandler` and showed
"Lesson not found" — a message about a missing lesson to someone who
hadn't named any lesson at all. The cause had two parts: first, the
service had no `GET /` route; second, a unit test on `/e/<slug>`'s headers
(calling `buildHandler` directly) couldn't have caught this, because a
real `shelf_io.serve`/`dart:io`'s `HttpServer` adds `X-Frame-Options:
SAMEORIGIN` to every response itself, bypassing `_securityHeaders()`'s own
code — a difference visible only through a real HTTP request to a running
process, not through a direct `Handler` call in a test. The second part
was already closed before the first deploy (`location /e/` in nginx
carries `proxy_hide_header X-Frame-Options`, confirmed with `curl`, both
directly against `dart run` and through nginx). The first part is a new
`GET /` listing lessons from `lessons_registry.dart` (`homePage()`), plus
`lessonNotFoundPage()` split out from the general `notFoundPage()`
("Page not found"), so the two different "not found"s don't get mixed up
again. Rebuilt and redeployed to `lessons.pleion.dev` the same day.

**A real bug, found by curl against the live address, not by a test.** The
first check of `/e/engine-tour` on the real `lessons.pleion.dev` showed
`x-frame-options: SAMEORIGIN` — exactly what shouldn't be there. The cause
wasn't in this code: `dart:io`'s `HttpServer` sets `x-frame-options` (and
`x-xss-protection`, `x-content-type-options`) on every response itself, by
default, at the transport level, before `shelf` even builds a `Response`
object — reproduced on a bare `HttpServer` with not one package on top,
on two independent machines (this one and `bob`). `shelf` gives no way to
reach `dart:io`'s own `HttpHeaders` and delete a preset key: leaving
`x-frame-options` out of `shelf`'s own `Response` header map (which
`_securityHeaders` in `app.dart` correctly does) isn't the same as the
header being absent on the wire. `dart test` doesn't catch this, because
it calls `Handler` directly, bypassing `shelf_io`/`dart:io` entirely — a
test remains proof of the code's own intent, not proof of what goes out
over the network (see `app_test.dart`'s own comment above this test). The
real fix sits a layer lower:
`cloud/lessons/deploy/nginx-lessons.pleion.dev.conf`'s own separate
`location /e/` with `proxy_hide_header X-Frame-Options` — only nginx sees
`dart:io`'s finished response and can strip the header from it.

**Deployed on 2026-09-12.** `lessons.pleion.dev` is live:
`flutter3d-lessons.service` (Dart, `127.0.0.1:8796`), nginx on `8795`, its
own cloudflared tunnel, `flutter3d-lessons`
(`213747ad-6172-4e98-97dd-4b72d406f355`), and its own DNS record —
separate from `models.pleion.dev`'s own tunnel and nginx, as Dmitrii
asked. Ports `8795`/`8796` were confirmed free on `bob` before setup
(`ss -tlnp`), not simply taken from the plan. The service binary wasn't
built through `cloud/lessons/tool/build_server.sh`'s own Docker path
(Docker wasn't available locally), but compiled directly on `bob` —
`cloud/lessons/server` pulls in not one engine package by path (unlike
`cloud/server`), so `bob`'s own Dart 3.11 (above this package's own floor
of `^3.10.0`) built it with no cross-compilation; `build_server.sh` stays
in the repository for reproducibility, but the actual first deploy went a
different way — an honestly named divergence, not a silent one. Checked
live from outside: `https://lessons.pleion.dev/health`, `/l/engine-tour`
(a page with a working `<iframe>` onto `/app/`), `/e/engine-tour`
(`x-frame-options`/`content-security-policy` headers confirmed absent in
the real response, not only in a test), `/l/does-not-exist` → 404.

**`check` was added separately, laying groundwork for `edu-03`.** `edu-01`'s
own record already named this a gap: a panel could place a `check` as
data, but nothing rendered it or graded an answer anywhere.
`apps/flutter3d_lesson_viewer/lib/src/check_prompt.dart` —
`CheckSpec.fromStep` (honestly reads `question`/`answers`/`attempts`,
answers `null` for an incomplete or missing `check`, rather than
throwing), `CheckSpec.accepts` (a case- and whitespace-insensitive
comparison — the content-level mitigation `edu-00` §10 itself suggests,
not requires), `CheckPrompt` — a widget with an answer field, an attempt
counter, and revealing the answer once attempts run out. The result is
visible only locally (`edu-00` §10 itself doesn't decide where it goes) —
exactly the first of the two cases that should exist before `edu-03` gives
a second. `tour.json` got a fourth step, `quiz-steps`, with a real
question ("How many views does this tour show?"), in
`edu_sequence.steps`. `CheckPrompt` deliberately doesn't remember which
step it is: resetting the attempt count between steps is an ordinary
Flutter `ValueKey` by the step's own name, rather than a second field that
would have to stay in sync with the player's own index. 10 new tests in
`check_prompt_test.dart`, `flutter analyze` clean — but, as the next
paragraph shows, "green tests" here meant "not covering the real path."

**A fourth live-run bug: a red screen, a rollback, and why the rollback
turned out to be temporary.** `flutter run -d chrome` on the real
`quiz-steps` showed Flutter's own default `ErrorWidget` — not one of these
10 tests caught it, because all of them exercise
`CheckPrompt`/`CheckSpec` in isolation or wrap it in a `Scaffold` (which
itself gives a `Material` ancestor), rather than in the bare tree
`MaterialApp(home: LessonView(...))` that `main.dart` actually builds. The
session that found this was interrupted mid-log-reading — it managed to
roll `quiz-steps` back out of `edu_sequence.steps` (deleting neither the
entity nor `check_prompt.dart`) and to write an honest note here: "cause
not found, do not restore without a fresh reproduction." The next session
reproduced the crash and found the exact cause: a `TextField` inside
`CheckPrompt` requires a `Material` ancestor (`debugCheckHasMaterial`), and
`main.dart`'s own `LessonReady` branch hands out a `LessonView` with no
`Scaffold` — `_loading()`/`_didNotStart()` carry one, the finished lesson
screen doesn't. The fix — `LessonView.build()` wraps itself in a
`Material(type: MaterialType.transparency)` (paints nothing, only gives an
ancestor), rather than relying on calling code to provide one. A new test
in `lesson_view_test.dart` reproduces exactly the tree `main.dart` builds
(`MaterialApp(home: LessonView(...))`, no `Scaffold`) with a step carrying
a `check`, and checks `tester.takeException()` — a test that would have
caught this from the start, had it existed before the finding.
`quiz-steps` is back in `edu_sequence.steps`, the lesson's own description
mentions the question again, `lesson_cubit_test.dart` covers four steps.
Rebuilt and redeployed. The lesson for the next session is the same one
already written three times in this file: a test wrapped in a `Scaffold`
for convenience is not a test of the tree the real application builds.

**Not done, named plainly:**
- `offsets`, `edu_clip_plane`, `bindings`/`edu_data_source` — each honestly
  not included, per `lesson_player.dart`'s own doc comment.
- `edu-03` (LTI/xAPI) hasn't started.
- Uploading one's own lesson — a registry in code, not a form or a
  database; the same unbuilt infrastructure `cloud/server`'s own README
  already names for its own "public catalog."
- A full live browser run (with no crash, including embedding in a
  third-party `.html`) wasn't finished end to end — what was covered found
  the bug above, rather than confirming readiness.

### tpl-01: `init --template=<genre>` — the mechanism was reused, not written from scratch

Closed 2026-09-12, with the same caveat as ai-00/ai-01/par-03: a literal
`dart run flutter3d:init` is again `flutter3d_build`/`ap-10`, which doesn't
exist and itself depends on the whole
`ap-00→ap-02→ap-03→ap-04→ap-05` chain
(`doc/asset-pipeline-plan.md`) — a separate, multi-week plan, not part of
this wave.

**A real finding before a single new line of code: almost the whole
mechanism already existed.**
`packages/flutter3d_editor_core/lib/src/scaffold.dart` and
`scaffold_templates.dart` — `Template`, `scaffold`, `projectAt`,
`packageName`, `pubspecFor`, `readmeFor` — are already written, already
tested (`apps/flutter3d_editor/test/templates_test.dart`, a long file
covering all four genres) and already used by the "new project" wizard
inside the editor itself (`apps/flutter3d_editor/lib/main.dart`, calls to
`Template.parse`/`scaffold`/`projectAt`). Four templates (`platformer`,
`racing`, `shooter`, `strategy`) already sit in
`apps/flutter3d_editor/assets/templates/` — a manifest, a starting level
with no `generatedBy`, the genre's own word palette, models, and — most
important for this task — already-ready
`app.main.dart.txt`/`app.backend.dart.txt` seed files, rather than the
thousand-line `main.dart` of a real demo. `pubspecFor` already writes
published versions (`flutter3d: ^0.6.0` and so on), not `path:`
dependencies — meaning a finished project is already portable outside
this checkout, exactly the task's own "travels" condition.

So tpl-01's own, not-yet-done part is only one seam: the same mechanism,
called from a bare `dart run` rather than from inside a running Flutter
application (which reads a template's bytes through `rootBundle`).
`tool/init` (a flat Dart package under `tool/`, not under `packages/`, the
same trick `tool/skills`/`tool/convert_asset` already use) —
`writeProject()` reads the same files directly off the editor's own disk
with `dart:io`'s `File.readAsBytesSync()` and hands them to the same
`scaffold()` the wizard already calls; `availableTemplates()` reads
`templates/index.json` for `--list`. `bin/init.dart` — `dart run
tool/init/bin/init.dart --template=racing --target=<dir>` and `--list`,
honestly named, not `flutter3d:init`.

Idempotency (the acceptance's own wording: "a second `init` is an empty
diff") is by construction: copying is unconditional, sources don't change
between calls, meaning byte-identical output — checked both by a test and
by hand with the real CLI (`shasum` before and after a second call on a
real temp directory match).

Eighteen tests in `tool/init/test/init_writer_test.dart`: `--list` names
exactly four genres in the given order; an unknown genre names the genres
that actually exist, rather than an opaque crash; and for each of the four
genres — the right `pubspec.yaml` is written (the project's name, no
`path:` at all, the engine version in place), a starting level with no
`generatedBy` really reads, every file from the manifest really lands on
disk, running it again gives a byte-identical tree.

Not done: the literal `dart run flutter3d:init` (`ap-10`); real asset
conversion through `ap-05` (`assets_src/`, which `ap-11`'s own path
doesn't yet know how to read, so the template keeps carrying ready-made
`.glb` files, the same as today's editor wizard); building templates in
CI — a separate infrastructure task, not part of `init`'s own code.

### tpl-03: the "new project" wizard in the editor — already existed, "name" was added

Closed 2026-09-12. **A real finding before a single new line of code:
almost the whole task was already done earlier, in this same tree, with
no record of it in this plan.** `EditorChooser`
(`apps/flutter3d_editor/lib/src/editor_chooser.dart`) already showed the
four templates as a list, tapping one wrote a project through
`scaffold()`/`projectAt()` and immediately opened the resulting level —
exactly tpl-03's own acceptance: "a project is created with no terminal on
macOS." It had neither its own section in `doc/tooling-plan.md` nor its
own test (a `grep` over `apps/flutter3d_editor/test/` for `EditorChooser`
found nothing) — working code with no record that the task was closed, and
no regression protection.

**What was missing per the literal wording — "a template, a name,
platforms":** the project's name was never asked before — it was silently
taken from the `kLevelPath` directory (an environment variable for
launching, not something a person types). Meanwhile `packageName(String
typed)` in `flutter3d_editor_core/lib/src/scaffold.dart` already existed
exactly for this — it takes arbitrary text and turns it into a
package/directory name — and nothing in the UI called it. A `_NameDialog`
dialog was added (its own `StatefulWidget`, not a bare
`TextEditingController` wrapped around `showDialog` — `Navigator.pop`
starts the closing animation, and the future `showDialog` returns resolves
before its last frame: a controller disposed right after that future
would be disposed while the `TextField` is still on screen — a real bug,
caught by a test, not guessed in advance). `_create` in `main.dart` now
places the project next to the current one (`kLevelPath`'s own parent
directory), rather than over it, under the name from the dialog.

"Platforms" from the wording weren't added — not an oversight, but a
mismatch between the wording itself and an architectural decision already
made for this editor: `apps/flutter3d_editor`'s own doc comment says
"Desktop only, and that is not an omission" — the editor has no web build
to choose alongside desktop, so the acceptance "in the browser the wizard
honestly says it doesn't run a build" doesn't apply literally either —
there is no browser version of the wizard itself, not a silent absence.

**A side finding while checking — a real cross-cutting bug between tpl-01
and tpl-04, not made up for the report.**
`apps/flutter3d_editor/test/scaffold_test.dart` holds all four seed
templates (`assets/templates/*/app.main.dart.txt`) byte-identical to
`apps/flutter3d_template_app/lib/main.dart` — the very principle tpl-01's
own finding already relied on ("a template is a copy of a real, compiling
application"). `tpl-04`, working in parallel, added 193 lines to
`flutter3d_template_app/lib/main.dart` (`WidgetSurface` support, reading
`edu_step`/`edu_data_source`) and a new file,
`lib/src/template_widgets.dart`, with no knowledge of this contract —
`flutter test` in `flutter3d_editor` went red. Fixed by resyncing: all
four `app.main.dart.txt` files were rewritten against the new
`main.dart`, the new file was added as
`app.template_widgets.dart.txt` in each template and listed in each
`index.json`. All 61 tests of `scaffold_test.dart`+`templates_test.dart`
and all 299 of the package's own tests are green after this; `dart run
tool/structure.dart` from the root — 32/32.

Three new tests in `apps/flutter3d_editor/test/editor_chooser_test.dart`:
tapping a template opens the dialog with a default name and passes
whatever's typed there into `onCreate`; canceling creates nothing; an
empty name after `trim()` also creates nothing.

### rp-01: the run file

Closed 2026-09-12. `Demo` (`flutter3d_sim/lib/src/save/demo.dart`) got
five new fields — `levelHash`, `buildStamp` and `checkpoints` required (the
same strictness `tape` already had: a missing field is an "unfinished"
file), `platform`/`recordedBy` optional. `.f3drun` is the constant
`Demo.fileExtension`, and `DemoFile` in `screens` now writes `demo.f3drun`
instead of `demo.json`. `DigestTrace` (an existing tool, from rp-00) got
`toJson()`/`fromJson()` — checkpoint digests serialize with the same
structure as the rest of the document. The level hash is a new free
function, `contentDigestHex(Map<String, Object?> json)`, in
`state_digest.dart`, rather than a method on `Level`:
`flutter3d_game_racing`'s `TrackDocument` doesn't write JSON back and can't
give a `Level`, so the hash is taken from the raw document on disk rather
than a parsed object — both forms give the same digest by construction
(`StateDigest`), so this is not two different hashes, but one tool over
two sources.

**The same thing was written a second time for strategy, for its own
reason.** `flutter3d_game_strategy`'s `MatchDemo` is a parallel format
(`OrderTape`, not `InputTape`), whose own header already explains why it
doesn't reuse `Demo` verbatim; the same five fields and the same
validation were added there too, the same way.

Acceptance:

- **"the file reads with `dart run`, no Flutter"** — not an argument, but
  a run: `packages/flutter3d_sim/bin/f3drun_info.dart`, a CLI script with
  not one Flutter import, and `test/f3drun_info_test.dart` (`@TestOn('vm')`)
  really runs `dart run bin/f3drun_info.dart <file>` as a separate process
  and checks the output. The same test checks the acceptance's second
  half — a file from a future format version is refused with a full
  sentence ("update flutter3d to open it"), not a crash.
- **"a write → read → replay → same digests test on each demo"** — five
  times, not four:
  `apps/flutter3d_demo_{dungeon,platformer,racing}/test/demo_test.dart`
  (genres on `Demo`/`InputTape`, played on a real shipped level/track) and
  `packages/flutter3d_game_strategy/test/match_test.dart` (`MatchDemo`,
  `mirror()` instead of a real map — strategy has none). Each: a live
  recording with a checkpoint every 25–30 steps → `Demo.toJson`/`jsonEncode`
  → `jsonDecode`/`Demo.fromJson` → a fresh replay → a byte-for-byte
  comparison of the snapshot, and `divergenceFromHex` for the replay's own
  trace against the recorded one. All five green on the first try, except
  racing (see below).

**One real finding along the way, not about the format but about the
engine's own input handling.** The racing test's synthetic driver first
released the throttle/steering through `clearActionValue`, and the replay
diverged from the live recording at the very first step where that
happened. The cause — `InputTapePlayback._apply` only *sets* the values a
frame names; it has no way to say "this is released," the same way a
polled analog device (a gamepad pedal, which `_readDriver` was written
for) never stops reporting as long as it's alive. `clearActionValue` is
about a device disconnecting, not a pedal being released; a released pedal
reports `setActionValue(action, 0.0)`. This isn't an engine bug
(`clearActionValue`'s own documentation says exactly this), but a wrong
use in the test — but the asymmetry is subtle enough to be worth
recording: any future recording code using analog actions must always
`setActionValue`, never `clearActionValue`, for a value that changes over
the course of a run.

Not done as part of rp-01, deliberately: permanently wiring demo recording
(`_beginDemo`/`_endDemo`) into platformer/racing/strategy — today it only
exists in dungeon. The format and its round trip are checked on every
genre; the wire "the player presses a button — a file lands on disk" for
the other three is not part of the format, and is explicitly named as
part of rp-04 in the plan itself ("In-game: 'send run' writes a
`.f3drun`").

### rp-05: a run into video and into a test

Closed 2026-09-12, with one correction to the plan's own wording.
`replayGolden()` is written in `flutter3d_testing`
(`lib/src/replay_golden.dart`) exactly as ordered: takes a `Demo`, a step
number, an `InputState` and a step callback (the genre decides how to
drive its own simulation), plays `InputTapePlayback` up to the step,
renders through the already-existing `renderFrame` and compares against a
golden through `expectMatchesGolden`. Three tests in
`flutter3d_testing/test/replay_golden_test.dart` on an empty scene (how
many times `onStep` fired, that a too-short tape throws a `StateError`
rather than rendering garbage, that a repeated run matches an already
recorded golden).

**Correction: `dart run flutter3d:replay` literally is not part of this
spike.** Checked empirically (`dart run` with a probe file in
`flutter3d_game_platformer`), not assumed: every genre package pulls in
the Flutter SDK transitively through `pointer_lock` (it needs `dart:ui`'s
`Offset`), so a bare `dart run` doesn't compile a single genre — only
`flutter3d_sim` (no Flutter) can be that kind of CLI, and "replay a demo"
for a specific game needs the genre package itself. `flutter3d:replay` as
a terminal command is the asset plan's own `flutter3d_build`/`ap-10`
(the package doesn't exist yet). The mechanism itself exists, and it's in
`apps/flutter3d_demo_dungeon/test/replay_video_test.dart`:

- **`--check`.** `checkReplay(Demo)` restores `demo.start` into a fresh
  build of the crypt, plays `demo.tape` at the same `_dt`, gathers its own
  `DigestTrace` and compares against `demo.checkpoints.hexDigests` through
  `divergenceFromHex`. A test: a real run converges (`null`); a tampered
  digest is named by step.
- **`--video`.** `renderReplayVideo(Demo, outputPath)` plays the same
  tape, draws every step through `flutter3d_cpu` (no GPU — the same
  `cpuTestDevice` as `frame_test.dart`), writes PNGs into
  `Directory.systemTemp`, then really runs `ffmpeg` (`Process.runSync`)
  and stitches them into a file. The test checks not that the code didn't
  crash, but that `ffmpeg` really created a non-empty file — meaning the
  video genuinely exists, not merely "the function returned."

Not done: `dart run flutter3d:replay file.f3drun --video out.mp4` as a
real terminal line (waiting on `ap-10`); ffmpeg is assumed to be on
`PATH` — checked to be present in this environment (`ffmpeg 8.1.1`), but
the CI machine may differ, and this wasn't checked here.

### edu-04: a virtual lab (a pendulum) — closed

Closed 2026-09-12. The acceptance names a school laptop with no GPU and a
live instructor scrubbing a student's own timeline — the same honest
narrowing already applied at ai-00/rp-05/net-04: "no GPU" and determinism
are proven through `dart test` with no Flutter GPU (the pendulum is moved
into its own package, `flutter3d_lab` — see below — which, like
`flutter3d_sim`, pulls in no Flutter SDK at all), and "an instructor
scrubs a student's own run in rp-02's timeline" is a UI opening this
session doesn't have; what exists is the real data and digest stream such
a timeline would read, proven by tests, not by a screen.

**The pendulum isn't a stub, it's real physics.** `PendulumSimulation`
(`flutter3d_lab/lib/src/pendulum.dart`) — not a `flutter3d_physics`
primitive (there are no hinge bodies there, and a pendulum is simple
enough that a general rigid-body machine buys nothing for its own extra
complexity): an explicit differential equation, `θ'' = -(g/L)·sin(θ) -
b·θ'`, integrated with semi-implicit Euler — the same order of accuracy
`GameSimulation` steps everything else with. The test "a longer pendulum
swings slower than a shorter one" checks not that the code compiled, but
that, after the same number of steps from rest, the short pendulum has
moved noticeably farther from its start than the long one — real physics,
not a number fitted to an expectation.

**A real `tool/structure.dart` finding, not only in this session's earlier
tasks.** The first version used `dart:math`'s `sin` directly — the "a step
asks no machine for an answer" rule caught this immediately: the standard
library's own trig functions go through the platform's `libm`, not
guaranteed to be the same path on the VM/web/different OSes — exactly the
divergence the whole rp-00/net-00 track guards against. Fixed with
`Portable.sin` (`flutter3d_sim/lib/src/math/portable_math.dart`), already
existing in the package for exactly this case — the pendulum isn't the
first thing that needs it, only the first in this session to have
forgotten it.

**`PendulumLabRun`** (`flutter3d_lab/lib/src/pendulum_lab_run.dart`) keeps
both a `DigestTrace` (rp-01's own verification mechanism: a checkpoint
every `checkpointEvery` steps) and a `DataSourceTrace` (edu-05's own
mechanism, reused rather than reinvented: the string length is exactly "a
value with no controller behind it," the same class as a sensor reading).
Every step is also stored whole (`_states`), not only at checkpoints —
without this, "what if" couldn't continue the pendulum from exactly the
state it was in, and would have to peek at the nearest checkpoint before
it instead.

**`branchAt` — a real branch, not a text description of one.** Takes the
exact state at step N, builds a NEW `PendulumSimulation` with it and
continues with a different length; the original run (its `pendulum`,
`checkpoints`, `lengths`) is untouched — the test compares the objects
before and after the branch is created byte for byte (`toJson()`), not
relying on the mutation simply not having happened. An honest finding
while writing the test: two pendulums of different lengths already
diverge at the very first checkpoint, not "after a while," as intuitively
expected at first — the digest is bit-exact, with no tolerance, and
`theta` after one step for two different lengths already doesn't match in
a single bit. The test was rewritten to what the check actually shows
(gives a nonzero, named divergence point), rather than a guess at what the
divergence should be.

**`toDemo` — a real `.f3drun`, not an imitation of the format.** The
pendulum has no geometry and not one `GameAction` — a student's panel
isn't a controller. That doesn't mean "the format doesn't fit":
`Level(name: 'pendulum-lab')` with no brushes is a valid, empty level;
`InputTape` made of steps with no button presses at all is exactly how a
run with no controller truthfully looks, and `DataSourceTrace`'s own doc
comment already names exactly this case. The test runs `toJson()` →
`Demo.fromJson()` and checks digests and `dataSources` byte for byte.

**A parameter panel through `WidgetSurface`, with buttons, not text.**
`PendulumLabPanel`
(`apps/flutter3d_lab_pendulum/lib/src/pendulum_lab_panel.dart` — its own
application, not `flutter3d_demo_dungeon`, where the panel originally
lived; moved by Dmitrii's own direct request: demonstrating the lab isn't
a dungeon-game mode) — "+"/"−" buttons, not a slider and not a text field,
`wg-01`'s own honest boundary: only a tap is proven to reach a widget on a
surface.

**One more real finding along the way, separate from the physics.** The
first version of the integration test tried to find the "+" button's own
coordinates through `GlobalKey.currentContext` — this didn't work, and not
from a typo: in this Flutter version, `GlobalKey.currentContext` reads
`WidgetsBinding.instance.buildOwner!._globalKeyRegistry`, not the registry
of the `BuildOwner` that actually built the element —
`WidgetSurfacePipeline` holds its own, separate `BuildOwner` (wg-00's own
decision), so a key registered there is invisible to the global binding in
principle, not only in this test. The fix isn't a hack, but an already
proven technique from `widget_surface_test.dart`: known geometry ahead of
time (`Align`+`SizedBox`), the same trick `wg-01` already used to check a
real ray reaching a real widget. The full integration test
(`pendulum_lab_panel_test.dart`) runs the whole chain: a tap on the surface
→ a real `PendulumSimulation.lengthMeters` changes →
`DataSourceTrace` records the new value at exactly the step it changed on,
not retroactively at step zero.

Twelve tests: eight in
`flutter3d_lab/test/pendulum_lab_run_test.dart` (physics, determinism,
divergence, branching, `.f3drun`, a panel changing the length mid-run) and
four in
`apps/flutter3d_lab_pendulum/test/pendulum_lab_panel_test.dart` (the
widget itself plus the full chain through a real `WidgetSurface`). Every
package — a clean `flutter analyze`, `dart run tool/structure.dart` —
32 of 32.

**A live demonstration (`apps/flutter3d_lab_pendulum/lib/main.dart`) — its
own application, not a mode of `flutter3d_demo_dungeon`, by Dmitrii's own
direct request.** A real swinging pendulum (a sphere bob on an invisible
axis, its position computed from `PendulumSimulation.theta` every frame), a
real `WidgetSurface` with `PendulumLabPanel`, a real tap through
`Raycaster` — the same path `flutter3d_template_app`'s own
`_tapWidgetSurface` already proved for `tpl-04`. Built and checked with a
live `flutter run -d chrome`, not only tests — and that's exactly how two
new facts turned up, neither caught by any existing test:

1. **`WidgetSurface.yaw` flips vertically if the panel is rotated before
   being tilted into vertical.** `SceneNode.setRotationYawPitchRoll`
   applies yaw before pitch; `WidgetSurface`'s own `yaw` setter always
   passes a fixed `pitch = -π/2` alongside it — meaning `yaw: 3.1416`
   (the very same value `edu-00`'s own `view-caption` already carries in
   `tour.json`!) flips the panel before it even stands vertical. Checked
   against `widget_surface_test.dart`'s own confirmed convention (`yaw = 0`
   looks toward `-Z`), not recomputed by hand a second time — the first
   hand recomputation in this same session had already been wrong.
   Practical consequence: the panel is left at `yaw = 0.0`, the scene's
   camera is moved to the side the panel already faces by default, rather
   than the other way around.
2. **A second, separate and not fully explained fact: `WidgetSurface`'s
   own content draws rotated a half-turn regardless of the node's `yaw` —
   not simply flipped along one axis.** Found by the same live run, in two
   passes: `Transform.flip(flipY: true)` (a vertical mirror) put the text
   right side up, but left it mirrored horizontally (letters backwards,
   "+"/"−" swapped) — something only a 180° rotation explains, not a
   mirror along one axis. Checked empirically, not merely observed: a test
   probe with a "red on top / blue on bottom" field on a real
   `WidgetSurface`, drawn through `flutter3d_cpu` and read back with
   `device.readPixels`, was meant to show which half ends up where. The
   probe itself ran into its own obstacle — `tester.pumpAndSettle()` hangs
   on the widget-surface pipeline (worked around with `tester.runAsync()`),
   and after that the read-back frame came out entirely black (0,0,0) on
   both halves — a second, separate, also unexplained finding, meaning the
   probe itself isn't proof there's no flip, not proof there is one.
   Further investigation (row/column order when loading the texture in
   `WidgetSurface.tick()`, `PlaneShape`'s own UV convention, the CPU/WebGL
   backend shaders) didn't fit this session's budget. **Temporarily worked
   around in `apps/flutter3d_lab_pendulum/lib/main.dart` through
   `Transform.flip(flipX: true, flipY: true)`** (a full flip) around
   `PendulumLabPanel` — working for this application, but not a fix for
   `flutter3d_session` for everyone else.

   **A third pass of the same live run: a tap after this workaround either
   hit nothing or hit the wrong button.** The screen shows the correct
   orientation (the point above fixes that), but `_tapPanel`'s own
   `uvAt(hit.point)` answers in the mesh's own coordinate system — the same
   one as before `Transform.flip` — while `dispatchAtUv` aims at the
   pipeline's own coordinate system, now rotated by that same
   `Transform.flip`. The first hand fix (symmetric to the point above:
   `Offset(1 - u, 1 - v)`) turned out wrong — a tap really landed on a
   button, but the wrong one ("+" acted as "−"); the correct one turned out
   to be only `Offset(u, 1 - v)` — `uvAt`'s own `u` already runs backwards
   relative to the pipeline, independent of the flip bug itself, and the
   second inversion on `u` was wrongly canceling that independent fact.
   Found live by pressing buttons, not recomputed — a second hand
   recomputation in a row in this same session, again giving the wrong
   answer.

   An open question for the next session: almost certainly the same thing
   awaits `edu-00` §7's own `view-caption` annotation in
   `flutter3d_lesson_viewer`, if it's ever wired into the widget registry —
   right now it doesn't render at all (an `Issue`, not a picture), so
   nobody has seen the bug there yet, either in display or in tap.

**The pendulum was split into its own package, `flutter3d_lab`, separate
from `flutter3d_sim`.** Not as part of `edu-04` itself — by Dmitrii's own
direct remark after it closed: `flutter3d_sim`'s own contract is "fixed
step, ECS, levels, navigation, saves, replays for games," and a specific
lab experiment's own physics doesn't belong in it, the same way a game
genre doesn't live inside `flutter3d_sim` but pulls it in as a dependency
(`flutter3d_game_shooter` and its neighbors). `flutter3d_lab` is a
plain-Dart package depending only on `flutter3d_sim` (`Portable`,
`DigestTrace`, `DataSourceTrace`, `Demo`/`Snapshot`/`InputTape`) — the same
reason for no Flutter as `flutter3d_sim` itself. Eight physics tests moved
with the code. 32 of 32 `tool/structure.dart` rules still hold (the
package was added to the "flat" list, to the publishing order next to
`flutter3d_sim`, and to the package/test counters). A direct dependency on
it first landed on `apps/flutter3d_demo_dungeon` (where the panel
originally lived), then moved wholesale to
`apps/flutter3d_lab_pendulum` along with the panel itself — see above.

Not done: a screen where an instructor really opens a student's own
`.f3drun` in `rp-02`'s timeline and sees the first divergence —
`DigestTrace.divergenceFrom` already names this step by number, there's no
panel over it for this specific scenario (the same honest boundary as
`rp-02`, `rp-04`, `net-03` themselves — the mechanism exists, the screen
for this specific case isn't wired in); a real school laptop wasn't
checked, only determinism and the absence of a GPU on the path; a level
with the pendulum isn't embedded in any template (`tpl-04` doesn't exist).

### rp-02: the timeline — closed

Closed 2026-09-12, after checking with the owner — noticeably further than
"the mechanism exists, there's no panel."

**Checked, not assumed: the level editor has no live playback today.**
`apps/flutter3d_editor/lib/` is `editor_cubit.dart`, `editor_palette.dart`,
`editor_inspector.dart` and their neighbors: brushes, entities, materials,
the inspector. `RunPlaying` is mentioned there exactly once, in a doc
comment in `editor_state.dart`, and is never built or used anywhere.
rp-02's own wording of "a pause/step/scrubber panel over `RunPlaying`"
assumes a "play the level live inside the editor" mode that doesn't exist
— a separate, larger piece of work, not part of rp-02 itself.

**What's done — the mechanism under the future panel, kept separate from
it**, the same logic as `wg-00`: prove it works first, draw the widget
after. `RunTimeline` in `flutter3d_session`
(`lib/src/run_timeline.dart`) is a generalization of the existing kill-cam
in `apps/flutter3d_demo_dungeon/lib/main.dart`
(`_startKillcam`/`_endKillcam`): `pause()`/`resume()`/`stepOnce()` are the
transport; `preview(secondsAgo)` is what `RewindBuffer.rewindBy` would
return with no side effects — what the scrubber shows while dragging;
`releaseAt(RewindPoint)` restores a frame, plays `tapeToPoint` with input
muted (like the kill-cam), then `RewindBuffer.cut()` — the game continues
from this point, rather than snapping back. Every call is written into
`history` (`TimelineCommand`) — "commands are visible in history,"
literally: a list the panel will be able to draw, and MCP will be able to
replay.

Six tests in `flutter3d_session/test/run_timeline_test.dart`, on the same
toy class as `flutter3d_sim/test/rewind_test.dart` (deliberately — a
stranger's toy can't be trusted, the same, already-proven class can be).
The main one: after `releaseAt(preview(3.0))`, the live state is checked
against an INDEPENDENT replay of the same three hundred steps from scratch
— not "the function didn't crash," but "landed at the exact same point,"
through a separate calculation. A bug was found and fixed along the way,
in the test itself, not in `RunTimeline`: the order "apply input → record
→ `beginStep` → check `keyframeDue`/take a keyframe → step → `endStep`" is
not the one that feels intuitive, and `GameLoop.advance` is the one source
of truth on this.

**The owner's own clarification changed the rest of the plan.** The first
thought was "an editor panel is needed on top of this mechanism" — but
`apps/flutter3d_editor` is genre-agnostic: it edits a `Level`, knows not
one `EntityKind` and can't build a simulation to play it. `ROADMAP.md`'s
own plan for "the editor launches a project" is not to embed a simulation
into the editor, but to connect to an already-running application through
the VM service, the same channel DevTools and `flutter attach` use. The
owner's decision on 2026-09-12: build it exactly that way.

**And that channel is now real, not designed on paper.**
`registerTimelineExtensions(RunTimeline)` in `flutter3d_session`
(`lib/src/run_timeline_extensions.dart`) hangs `RunTimeline` off
`dart:developer`'s service extensions —
`ext.flutter3d.timeline.pause`, `.resume`, `.stepOnce`, `.preview`,
`.releaseAtStep`, `.history` — through the same `registerExtension`
`flutter_driver` and DevTools reach a live application with. Proven not
with a mock, but with a real second process:
`test/run_timeline_extensions_test.dart` (`@TestOn('vm')`) launches
`test/fixtures/timeline_target.dart` (a toy simulation ticking on its own
timer, with the extensions registered) as `flutter test
--enable-vmservice -v` in a separate process, parses a real VM service URI
from its stdout (the same one DevTools sees), connects with
`package:vm_service` — the same library DevTools itself is built on — and
drives `pause`/`stepOnce`/`preview`/`releaseAtStep`/`history` over the
wire. The test checks not only the answers, but also that the command
history, read remotely, is exactly what was sent, in order; along the way
it turned up (and needed no fix, because it turned out to be correct
behavior) that `releaseAt` already lifts the pause itself, so a `resume`
after it is a legitimate no-op, not a bug.

**A panel now exists too, inside the editor itself.** A seventh extension,
`ext.flutter3d.timeline.status` (`{"paused": bool}`), is how the panel
learns the state right after connecting, rather than guessing.
`TimelineClient` in
`apps/flutter3d_editor/lib/src/timeline_client.dart` — an interface plus
`VmServiceTimelineClient`, wrapping `package:vm_service` (the same
`http://` → `ws://` conversion as in the test). `TimelineAttachScreen`
(`lib/src/timeline_attach_screen.dart`) — pause/resume, step, a "how many
seconds ago" field with a preview button, a "Release here" button, a
history list; it polls `status()`/`history()` again after every action,
rather than holding its own copy of the server's state. Seven widget
tests (`test/timeline_attach_screen_test.dart`) on a fake `TimelineClient`
— not a second real process, like the protocol itself, but an ordinary
mock: buttons are disabled/enabled correctly, a preview shows the found
step, `Release` calls `releaseAtStep` with that step, a client error
shows on screen rather than being swallowed. The entry button — an icon in
the corner of the editor's main screen (`Icons.podcasts`), a dialog asking
for the VM service URI, opening the panel on success, writing an error to
the editor's own status line on failure, breaking nothing. `flutter build
macos --debug` for the whole application is green.

**And now checked on a real game, not only a toy.**
`apps/flutter3d_demo_dungeon/lib/main.dart` set up `_timeline` (the same
`RunTimeline`, re-reading `_sim`/`_input`/`_rewind` on every call, because
`_sim` is a getter, not a field, and changes when the level changes) and
calls `registerTimelineExtensions(_timeline)` in `initState`. The built
`dungeon.app` was actually launched (`flutter run -d macos`), and a
separate Dart script outside the repository — using the same
`package:vm_service` as `VmServiceTimelineClient` — connected to its real
VM service and got real answers back: `status` → `{"paused":false}`,
`pause` → `{}`, `status` again → `{"paused":true}`, `stepOnce`, `history`
→ `{"commands":["paused","stepped"]}`, `resume`. Not staged — a live
process of an application built in this same session.

**The boundary of what's checked is named honestly.** The game was at the
menu screen — `_step` in `main.dart` returns immediately if
`_sim`/`_player` are still `null`, meaning `_rewind` doesn't gather frames
while no level is actively being played; `preview` on the real game
therefore answered `{"found":false}` — correct, not a bug, an honest
"there's nothing to show yet" answer. Getting a level to "played a bit,
there's something to scrub" and repeating the check from there needs a
click through the menu, which this session has no means to do (no visual
access to the native macOS window) — the rewind/release logic itself is
already separately proven both on the toy
(`run_timeline_extensions_test.dart`) and by `RunTimeline`'s own unit
tests, so the gap is only that "a real game plus an active play session
at once" weren't proven together in a single check. The button in the
editor itself (`Icons.podcasts`) also wasn't clicked in an open window —
only seven widget tests on a fake and a successful `flutter build macos`
build. Scrubbing across the whole length of a `.f3drun` (restoring from
the nearest checkpoint, not through `RewindBuffer`) is separate,
unbuilt logic.

**An update the same day: two protocol extensions and two panel elements
were added on top — what closes rp-04 and rp-06 in the panel, not only in
the mechanism.** `registerTimelineExtensions` got two more optional
parameters — `frameTimes` (`StepTimeTrace`) and `bugReport`
(`Map<String, Object?> Function()`) — registering `.frameTimes` and
`.bugReport` the same way as the first seven; optional, because not every
caller has them. `run_timeline_extensions_test.dart` checks both through
the same second process as everything else — `timeline_target.dart` now
gathers a `StepTimeTrace` and hands back a toy bug report (`{x, step}`),
both read back over the wire. `TimelineClient` and
`VmServiceTimelineClient` (`timeline_client.dart`) got
`frameTimes()`/`bugReport()` through the same `_call()` as the other five
commands. See the details of the closed status below, in rp-04 and rp-06
themselves.

**And the last of the named gaps — a scrubber across the whole length of
a `.f3drun`, not only the live `RewindBuffer` window — is closed too, the
same trick as above: the mechanism stands separately, the panel doesn't
know what's underneath.** `rewindBufferFromDemo` in `flutter3d_session`
(`lib/src/demo_timeline.dart`) is not a second scrubber implementation,
but a way to get what `RunTimeline` already does for the whole file,
rather than only the last N seconds of a live game: it restores
`Demo.start`, plays its whole `InputTape` through `stepSim` in the exact
order `GameLoop.advance` uses (apply the recorded frame → `record` →
`beginStep` → take a keyframe if it's due → step → `endStep`), into a
fresh `RewindBuffer` with `history` deliberately larger than the whole
run's own length — so `_forget()` never kicks in, and every step stays
reachable. The result is an ordinary `RewindBuffer`, and the `RunTimeline`
built on it answers `preview`/`releaseAtStep` for any step of the whole
file with the same panel code already proven for a live window: neither
`TimelineAttachScreen` nor the `ext.flutter3d.timeline.*` protocol knows
whether the `RewindBuffer` it's fed was restored from a file or just
recorded. This also happens to close "the branch is written as a separate
file" from the original wording: since `RunTimeline` doesn't distinguish
a run restored from `Demo` from a live one, the "Save bug report" button
(rp-04) works on it unchanged — a bug report taken at any point of the
run already is exactly that separate file.

Three tests in `flutter3d_session/test/demo_timeline_test.dart`:
`RunTimeline` on a restored buffer reaches 9.5 seconds back in a run that
lasts ten seconds total — exactly what a live buffer with the default
`history: 10.0` couldn't reach (a live buffer's first keyframe can't
predate when recording into it began, while a restored one holds the
whole run from step 0); the landing point is checked against an
independent replay of the same tape from `Demo.start`, not merely that
the function didn't crash. Separately — `preview` past the tape's own end
finds nothing, and the `InputState.muted` flag doesn't leak out after
reconstruction, the same trick `RunTimeline`'s own `releaseAt` uses.

The honestly named boundary here differs from the rest of rp-02: this is
a `flutter3d_session` function, proven by three unit tests on a toy, not
wired into any real application — neither `dungeon` nor the editor knows
today how to "open a `.f3drun`" through this function, so it isn't checked
by a second process over the VM service (as the first half of rp-02 was).
The wiring itself — "open a file → build a `RunTimeline` on the restored
buffer → register the same extensions" — isn't new work: the same
sequence already exists in `dungeon` for a live game, over the finished
function instead of `RewindBuffer()`. The same class of limitation as
rp-04/rp-06: clicking a button in an open editor window, and "a real game
in the middle of an active play session, not the menu" — this session
still has no means to automate a native macOS window.

### rp-03: re-simulating after a level edit

Closed 2026-09-12. rp-03 is two different claims under one item, and they
weren't the same size, but both are closed.

**"A wall is moved, the run continues on the new geometry" was already true
by construction, and that was worth checking, not assuming.** `Snapshot`
never names a brush: `Level.addTo` rebuilds every collider fresh from
whatever document is loaded, and `CharacterController`'s own state —
position and velocity — is about neither one in particular.
`packages/flutter3d_sim/test/resim_after_level_edit_test.dart` — two
tests: (1) a level is played with a wall in the way, a snapshot is taken
right as it's blocked, the wall is removed in the new version — the run
continues and moves past the point it used to stop at, with not one
exception; (2) the reverse case — a wall appears where there used to be
empty space, and the restored run stops against it on the very next step,
even though the snapshot knew nothing about this wall. Both green on the
first run.

**"A level with a monster removed doesn't crash and names what was
dropped" — the mechanism was found, built and carried through in two
genres.** The first attempt at a solution concluded "the ECS core needs a
patch" — wrong: `EcsWorld.restore` really has nothing but a raw integer
index (`_generations`/`_free`, component rows keyed by `value.key` = index),
but the class itself isn't required to know about this difference, because
nothing in `restore` checks that the document came from *this same*
`save()`, rather than being assembled fresh from outside.
`remapEntitySave` in `flutter3d_sim`
(`lib/src/ecs/entity_remap.dart`) is exactly that outside reassembly:
takes JSON from `EcsWorld.save()`, two "index → name" lists (for the old
and the new world) and rewrites component keys from the old index to the
new one by matching name, returning whatever found no name — and whatever
was never named at all — as a separate list, instead of letting it
silently vanish. Four tests in
`flutter3d_sim/test/entity_remap_test.dart`, on a real `EcsWorld` (not a
stand-in dictionary): of three named monsters, the middle one (an archer)
is removed, and an ogre spawned in the new world after a guard lands on
exactly the archer's old index — the test checks that after the remap the
ogre gets its own health (90), not the archer's (18), which is exactly the
mistake the whole mechanism exists to catch. Plus a lossless reorder and
two refusal cases (an unnamed entity; a name that doesn't exist in the new
level at all).

**Carried through to a real genre**, after checking with the owner: `Actor`
got an optional `name` field
(`packages/flutter3d_sim/lib/src/actors/actor.dart`),
`ActorSystem.spawn({..., String? name})` accepts and stores it, `byName()`
looks it up (the same thing `MechanismWorld` already knew how to do),
`nameList()` builds an "index → name" list in exactly the shape
`remapEntitySave` asks for — so the calling code doesn't need to assemble
its own list, only pass it on both sides of the edit. The name was carried
from the document to the actor in two genres:
`EnemyKind.spawn` in the platformer
(`entity.name` → `actors.spawn(..., name: entity.name)`) and
`MonsterKind`/`Bestiary.spawn` in the shooter (the same thread through two
layers rather than one — `Bestiary.spawn` got the same optional
parameter). Both genres — `flutter analyze` clean, old suites untouched
(platformer 221/221, shooter 347/347). A dedicated test,
`flutter3d_game_platformer/test/entity_remap_test.dart`, builds three
named enemies through a real `EnemyKind`, removes the middle one and
checks through `ActorSystem.nameList()`/`byName()` — no longer stand-in
names, but what actually went through the game's own code — the same
finding: the ogre gets its own ninety, not the archer's eighteen.

Not done: racing and strategy are untouched (racing has no actor-monsters
at all — only cars; strategy is built differently, its units are already
their own entities with an ID through `OrderTape`, not through
`EntityDef.name`) — giving them names for the sake of uniformity no real
scenario asks for would be work with no scenario. The full wire "a person
edits a level while paused, sees what got dropped in the UI" still waits
on a live play mode in the editor — the same limitation as rp-02/rp-04.

### rp-04: a bug report as a run — the file now opens with a double click

Partially closed 2026-09-12. `bugReportTape(RewindBuffer)` in
`flutter3d_session` (`lib/src/bug_report.dart`) — "the last N seconds from
`RewindBuffer`," literally: takes `rewind.rewindBy(rewind.available)` (all
the frames the buffer still holds) and returns a snapshot of the oldest
held frame plus the whole retained tape — exactly what the calling code
assembles a `Demo` from (a level hash, a build stamp and checkpoints
aren't this function's own job, it has no simulation to compute them with
— the calling code already runs one). Three tests in
`flutter3d_session/test/bug_report_test.dart`: `null` before a single
frame has been recorded; a fifteen-second-old window is really no longer
than "history + one frame interval" — exactly what `RewindBuffer`'s own
documentation promises; and the tape itself replays, through an
independent run, to the exact same position the live game was at, and
through `Demo`/JSON and back.

**Added the same day: "send run" can now really be pressed — from the
editor, not only called as a function from a test.**
`registerTimelineExtensions` got an optional `bugReport:
Map<String, Object?> Function()`, registering an eighth extension,
`ext.flutter3d.timeline.bugReport` — through the same `dart:developer` as
the first seven; optional, because not every caller has one, and a
callback error turns into a `ServiceExtensionResponse.error` rather than
crashing the isolate. `apps/flutter3d_demo_dungeon/lib/main.dart` gives a
`_remoteBugReport()` callback that calls `bugReportTape(_rewind)` and
assembles exactly what would go into a `Demo`: the level, its hash, a
snapshot, the tape, the build stamp, the platform — as serializable JSON,
rather than the `Demo` class itself (the shape is the caller's own choice;
here it's chosen the same way deliberately, for symmetry). In
`TimelineAttachScreen` — a "Save bug report" button: calls
`client.bugReport()`, opens the system save panel (`file_selector`,
already a dependency of the editor) and writes the answer to disk.
Checked not with an in-memory fake, but a real `FileSelectorPlatform.instance`,
swapped for an implementation answering with a path in a temp
directory — `timeline_attach_screen_test.dart`, after pressing the
button, reads the file written to disk and compares it against what the
fake `TimelineClient` returned. The write is `writeAsStringSync`, not
async: a few kilobytes of JSON isn't the volume that justifies keeping a
write asynchronous, and (not obvious in advance) an async
`File.writeAsString` inside `flutter test` in this session's sandbox
hung dead — no exception, no timeout, literally never finishing; the
synchronous version in the same test finished instantly.
`run_timeline_extensions_test.dart` checks the same extension through a
second process, like the other seven.

**Added in a second wave of tasks the same day: a double click on
`.f3drun` in Finder really opens the editor — checked with a real `open
-a`, not assumed.** `Info.plist`'s `CFBundleDocumentTypes`/
`UTExportedTypeDeclarations` declare `.f3drun`
(`dev.pleion.flutter3d.run`) as a type owned by `apps/flutter3d_editor`;
`AppDelegate.swift` overrides `application(_:open:)` — the modern
replacement for the deprecated `application(_:openFile:)`, one for both
cases ("opened by a double click at a cold start" and "dragged onto the
dock icon while the application is already running") — and forwards the
path into Dart through a `FlutterMethodChannel`, buffering it if the
channel doesn't exist yet (launching by double click calls this method
before `FlutterViewController` is even up).

Checked live, not by inspection: `flutter build macos --debug` built a
real application, `lsregister` registered it with Launch Services, and
`open -a editor.app test.f3drun` — the exact same path Finder uses to open
a file by double click, not an imitation of it — really reached
`application(_:open:)` (confirmed by a temporary write of the path to a
file on disk during the check, later removed — the fact of the call with
the right path, not code that "should work"). `OpenRunChannel` on the
Dart side is a thin wrapper over `MethodChannel`, with two tests on a real
simulation of the platform call
(`TestDefaultBinaryMessengerBinding.handlePlatformMessage`, not a mock of
the logic over the callback) in `open_run_channel_test.dart`.

**A screen for the file to open into didn't exist at all before — it's
built now.** Nobody in the editor read `Demo.fromJson`: `.f3drun` could
only be written (by ai-00, the "Save bug report" button). `run_info.dart`'s
`parseRunFile` is a pure function parsing text into a `Demo` with the same
three outcomes as every other versioned format (not JSON at all, not an
object, not a `Demo`, an outdated version) — five tests on a real
`Demo.toJson()`/`fromJson()` round trip, not a made-up schema.
`RunInfoScreen` isn't a scrubber: it shows what the file claims (the
level, its hash, the build stamp, the platform, the step and checkpoint
count), rather than playing it — the same honest boundary already named
by net-04's own `diff` and rp-05's own `replayGolden`: only the genre
itself knows how to step its own simulation, and the editor knows none.
It opens the same way through three paths: a file association, a button
in the panel (`file_selector`, the same pattern as ai-02/edu-01), and —
for the future — anything else that calls `_openRunAt`. Two widget tests
in `run_info_screen_test.dart`.

**Closed on 2026-09-13 for platformer and racing.** `_rewind`/`_timeline`/
`_remoteBugReport()` from dungeon's own `main.dart` aren't a new
mechanism, but the same one: `RewindBuffer(stepsPerSecond: 60, history:
10.0)` in both applications, `_loop.recorders.add(_rewind.recorder)`,
`registerTimelineExtensions(_timeline, bugReport: _remoteBugReport)`, and
`if (_rewind.keyframeDue) _rewind.keyframe(sim.save())` right before the
step itself — `PlatformerSimulation`/`RacingSimulation` already carried
`Snapshot save()`/`restore(Snapshot)`, which exist exactly for this (the
same contract rp-00/rp-01 already checked). For racing, `levelHash` is
honestly empty: `TrackDocument` has no `Level` to hash from (the same
finding as rp-01), and re-reading the file just for one diagnostic field
would mean making the callback async with no real need — the same tape
and snapshot already replay the run without it. `flutter analyze`/`flutter
test` are clean on both applications (236 and 184 tests).

**strategy — not the same wire, but a different reason, not blurred
together with the previous two.** `RewindBuffer.recorder` is an
`InputTapeRecorder`, it writes `GameAction`'s own continuous state every
step; strategy simply has none of this state — a `grep` over
`apps/flutter3d_demo_strategy/lib/main.dart` finds neither `InputState`
nor `GameAction` at all, the same way `tpl-02` already found for its own
tape. A match is played through discrete orders via `CommandPost`
(`OrderTape`, not `InputTape`), and setting up a `RewindBuffer` over
continuous input that doesn't exist isn't a missing wire, but the
mechanism itself, which this genre cannot carry with no second kind of
buffer invented for discrete orders. This is the same root tpl-02 already
honestly named, not a separate, new rp-04 gap. **Drag-and-drop on the web
build isn't built, for a reason bigger than "platform UI": `apps/flutter3d_editor`
has no web build at all.** The application's own doc comment names this
plainly: "Desktop only, and that is not an omission — this application
exists to write a file back over itself, which a browser will not do" —
a task set for a target that doesn't exist, not an unfinished part of one
that does; building the editor a web backend just for this one capability
would mean reversing an architectural decision this same plan doesn't
revisit. The cloud (an upload, a link, a run page) is `cloud/server`,
where another session in this session is already doing parallel work —
left untouched, to avoid a collision.

### rp-06: a per-run-step profiler — closed

Closed 2026-09-12. `StepTimeTrace` in `flutter3d_sim`
(`lib/src/save/step_time_trace.dart`) — "a counter trace per pass, keyed
by run step," literally, the same serialization contract as `DigestTrace`
(`toJson`/`fromJson`, its own dedicated exception), only milliseconds
instead of a hash. `record(step, body)` is a `Stopwatch` wrapper for the
typical case; `observe` is for a caller whose time is already measured by
something else. `worstStep`/`worstMillis`/`meanMillis` are what a click on
a spike in the strip should show: not only "where it was bad," but where
the timeline should jump. Ten tests in
`flutter3d_sim/test/step_time_trace_test.dart` — the same set as
`DigestTrace`: every N steps, a JSON round trip, refusing on a length
mismatch, plus what's specific to time — `record` doesn't change the
wrapped call's own result, and a tie between two worst steps names the
first. Separately checked on `dart test -p chrome`.

**The strip over the scrubber now exists.** `registerTimelineExtensions`
got an optional `frameTimes: StepTimeTrace`, registering
`ext.flutter3d.timeline.frameTimes` (`StepTimeTrace.toJson` as is) the
same way `bugReport` does above at rp-04;
`apps/flutter3d_demo_dungeon` sets up a `StepTimeTrace` and wraps
`sim.step(dt)` in `_frameTimes.record`. `_FrameTimeStrip` in
`timeline_attach_screen.dart` — one strip per step from
`client.frameTimes()`, its height proportional to its own cost relative
to the trace's worst step; tapping a strip calls the same `releaseAtStep`
as the "Release here" button — "a frame-time spike is visible on the
timeline and a click on it jumps to the step," exactly §4.1's own
acceptance. The panel quietly shows "no frame times yet" if the caller
never registered a `StepTimeTrace` — "there's simply no trace" and "the
client answered with an error" are different things, and only the second
should alarm. Three new widget tests in
`timeline_attach_screen_test.dart`: an empty trace draws a caption, not
bars; N steps give N clickable bars, addressed by a `ValueKey<int>` on
the step number, not by index (`find.byType(GestureDetector)` also finds
`Tooltip`/`ListView`'s own internal gestures, not only the bars — worked
around with the key); tapping a bar adds `branched:<step>` to the history,
exactly like an explicit `releaseAtStep`.
`run_timeline_extensions_test.dart` checks the same protocol extension
through a second process.

The scrubber the strip is drawn over is `TimelineAttachScreen`'s own live
`RewindBuffer` (preview/release for the last N seconds), not a separate
slider across the whole length of a recorded `.f3drun`; that stays future
work for rp-02 itself, if it's ever needed — rp-06's own acceptance speaks
of rp-02's own timeline, not of that one.

### wg-00: input and redraw

Closed 2026-09-12. The mechanism is `WidgetSurfacePipeline` in
`flutter3d_session` (`lib/src/widget_surface_pipeline.dart`): keeps a
`BuildOwner` and a `PipelineOwner` alive between frames (unlike
`WidgetTexture`, which builds and tears down its own pipeline on every
call), marks itself dirty through
`onBuildScheduled`/`onNeedVisualUpdate` and redraws only on that flag; a
pointer enters through `dispatchAtUv` — a UV on the surface turns into a
local coordinate, `RenderView.hitTest` finds the target, and
`GestureBinding` itself is added to the hit-test path by hand
(`HitTestEntry`), because `pointerRouter.route` and closing/sweeping the
gesture arena live exactly in its own `handleEvent` — without this step a
lone `TapGestureRecognizer` never wins the arena. Neither fact came on the
first try — see the code's own comments and the test's own commit
history.

Correctness — three tests in
`packages/flutter3d_session/test/widget_surface_pipeline_test.dart`: (1) a
redraw doesn't happen unless something explicitly asked for one; (2) a tap
on a UV lands on the button under it, not next to it; (3) the full chain —
"a ray (`CollisionWorld.raycast`) → a point and a normal → a UV on the
box's face → a tap" — is green on the VM, Chrome dart2js and Chrome wasm.

The measurement — `widget_surface_pipeline_benchmark_test.dart` (and the
same thing mirrored in
`apps/flutter3d_demo_racing/integration_test/widget_surface_benchmark_test.dart`
for Android/iOS, for the same reason as in rp-00): sixty frames of a
512×512 surface with a text panel, every frame changing a value and
redrawing; separately — sixty calls to `redrawIfDirty()` with no changes
("the skip").

| Platform | A dirty redraw, ms/frame | A skip (not dirty), ms/frame |
|---|---|---|
| macOS (VM, a host, not a phone) | 0.699 | 0.0001 |
| Chrome dart2js (canvaskit) | 7.107 | 0.0017 |
| Chrome wasm (skwasm) | 6.810 | 0.0003 |
| Android (emulator, arm64) | 7.964 | 0.0002 |
| iOS (simulator) | 2.698 | 0.0001 |

**A skip is three to four orders of magnitude cheaper than a redraw
everywhere** — the whole case for `redrawIfDirty()` is confirmed by a
number, not only by logic. The browser (dart2js and wasm alike) and the
Android emulator sit in the same order of magnitude (7–8 ms), macOS and
the iOS simulator are noticeably cheaper (0.7 and 2.7 ms) — likely the
emulators pay more for the software compositing layer than for the 512²
redraw itself; a guess, not separately measured.

What's outside this scope: **an emulator or a simulator is not a phone.**
No physical Android or iOS phone is connected to this session, and an
emulator's own performance systematically differs from real hardware
(usually favorably, on the desktop it runs on — meaning the 7.964 ms for
"Android" here is likely more optimistic than a real budget phone, not
more pessimistic). The table settles "the mechanism works and isn't
infinitely expensive," not "what it will cost on a target device" — the
second needs `wg-01` measured on a real phone before a redraw budget is
announced. `wg-01` can start on this basis.

### wg-01: `WidgetSurface` — the node is built, the keyboard ran into a real Flutter SDK boundary

Closed 2026-09-12, honestly incomplete on one specific acceptance point —
not because it never got attention, but because it was checked and
doesn't work, for a reason outside this code.

**The scene node.** `WidgetSurface` in `flutter3d_session`
(`lib/src/widget_surface.dart`) — a `MeshNode` on a `PlaneShape`, stood
vertically (`pitch = -π/2`, the standard
`setRotationYawPitchRoll`) so that at `yaw = 0` its normal looks along
`-Z` — the same convention `flutter3d_bridge`'s own `ActorVisuals.yawFor`
already documents for an entity's direction. The material is
`LightingModel.unlit` with a texture from
`WidgetSurfacePipeline.currentImage()`, uploaded through
`GraphicsDevice.createTextureFromPixels` — the same path
`WidgetTexture.draw()` already uses, just repeated on demand rather than
once. `tick()` calls `pipeline.redrawIfDirty()` every frame and re-uploads
the texture only if it returned `true` — and forces ONE upload on the
first call regardless of that flag, because the pipeline's own first
frame is already drawn by its own constructor (see
`WidgetSurfacePipeline`'s own doc comment) and therefore isn't "dirty" on
the first check: without this fix, a static widget would never show at
all — a real test's own finding, not a guess made in advance.

**`uvAt` is the exact inverse of how `PlaneShape` places its vertices**,
rather than a second, separately derived rotation matrix: a world point
passes through `node.worldMatrix`⁻¹, and `local.x`/`local.z` directly give
`u`/`v` by the same formula the mesh's own generation uses — so
correctness doesn't depend on which `yaw` the surface stands at. `v` is
deliberately flipped relative to `PlaneShape`'s own (which grows along
with world Y): the pipeline's own `v` is screen-space, top to bottom, and
the flip is the only reading of "the top of the widget is the top on the
wall" that makes sense.

**Diagnostics.** `WidgetSurface.redrawCount` forwards
`pipeline.redrawCount` outward — the third acceptance point ("a frame with
no widget change doesn't redraw it") reads directly from it.

**The level document → the application's own registry.** A new entity
type, `widget_surface` (fields `widget`, `width`, `height`, inherited
`at`/`yaw`) — flat, with no `"properties"` wrapper, the same finding and
the same decision already documented in
`doc/edu-00-interactive-format.md`, §2.
`flutter3d_bridge/lib/src/widget_surface_visuals.dart` (a new dependency,
`flutter3d_bridge → flutter3d_session`, checked for the absence of a
cycle) resolves `entity.string('widget')` through a `Map<String,
WidgetBuilder>` the application hands it — the same scheme
`edu_annotation.widget` already chose for annotations in edu-00, not a
coincidence, but one principle applied twice. An entity named for
something not in the registry doesn't crash the level — it goes into
`IssueSink`, the same way `FixtureVisuals` already answers a model that
failed to load.

**What already works and is proven by real tests:**
- `packages/flutter3d_session/test/widget_surface_test.dart` (7 tests):
  orientation (the normal at `yaw=0` — honestly measured, not assumed,
  `(0,0,-1)`; rotation by `yaw` — around world Y, like `ActorVisuals`),
  `uvAt` (a point at the center, a point at the edge, a point off the
  plane/past the edge), `tick`/`redrawCount` (doesn't grow with no
  changes, grows by one on a change, doesn't grow again after), and the
  full chain — "a ray (`CollisionWorld.raycast`) → `uvAt` →
  `dispatchAtUv` → a tap" — the same standard as `wg-00`.
- `packages/flutter3d_bridge/test/widget_surface_visuals_test.dart` (4
  tests): an unknown widget name doesn't crash the level; an entity
  resolves, the scene really holds the node (`scene.meshes`), and a ray on
  a node the bridge itself built (not the test by hand) really changes
  the widget; `tickAll` paints several surfaces at once; `dispose` removes
  the nodes from the scene.
- `packages/flutter3d_session/test/widget_surface_keyboard_test.dart` (2
  tests, honest, not about `TextField` — see below): a tap requests focus
  inside the surface on ITS OWN isolated `FocusManager`, not on the
  application's global one — read from Flutter's own sources, not
  assumed: a `FocusNode`'s own manager resolves through
  `context.owner.focusManager` (`focus_manager.dart`), where `owner` is
  the element's own `BuildOwner`, not a singleton; and two surfaces hold
  focus independently, because each has its own manager.

**A real finding along the way, not in this code: `TextField` inside an
isolated `WidgetSurfacePipeline` can't open a real text-input
connection.** Two independent Flutter SDK walls, both reproduced, not read
from an issue tracker:

1. `TextField` finds its own `EditableTextState` through a `GlobalKey`, and
   `GlobalKey.currentState` is
   `WidgetsBinding.instance.buildOwner!._globalKeyRegistry[this]`
   (`framework.dart`) — the registry of the application's ONE `BuildOwner`,
   not of a specific element's own `context.owner`. An element built by
   any other `BuildOwner` registers somewhere this lookup never looks.
   Reproduced: a tap on `TextField` here throws "Null check operator used
   on a null value" inside
   `TextSelectionGestureDetectorBuilder.editableText` — every time, with no
   involvement from the rest of the pipeline.
2. Even a bare `EditableText` (no `TextField`, no `GlobalKey`) still calls
   `View.of(context)` unconditionally inside
   `EditableTextState.textInputConfiguration` (`editable_text.dart`), to
   stamp a `viewId` on the connection. `WidgetSurfacePipeline` deliberately
   has no `View` ancestor — it builds its own `RenderView` directly,
   because the surface isn't a second window. Reproduced twice: with no
   `View`, `View.of` throws immediately; a `View` added inside the
   pipeline's own tree throws its own exception on mounting — "cannot
   maintain an independent render tree at its current location" — because
   `View` refuses to attach inside an already-attached
   `RenderObjectToWidgetAdapter`.

Neither wall is in this package, and neither is fixable from inside it —
both are Flutter SDK decisions that an application is singular, above the
level at which the pipeline can work around anything. wg-01's own
acceptance — "a text field on an in-game screen accepts keyboard input" —
is therefore not literally met, and this is named plainly, rather than
hidden behind a `TextField` that looks like it works while silently
swallowing every character.

**A real bug was found and fixed along the way in `wg-00`'s own code**,
not only in wg-01: `WidgetSurfacePipeline.dispatchAtLocal` recomputed the
hit test on every event, rather than reusing the one found on `down` — a
divergence from what the real `GestureBinding._handlePointerEventImmediately`
does (its own comment names the reason: "events that occur with the
pointer down... should be dispatched to the same place their initial
PointerDownEvent was"). For a tap, this isn't visible (down and up are at
the same point), but for a scroll it was a silent difference: an ordinary
`GestureDetector.onVerticalDragUpdate` through `dispatchAtLocal` reacted to
a synthetic down/move/up sequence, but `Scrollable` (both `ListView` and
`SingleChildScrollView`) did not, given the exact same event sequence on
the exact same proven setup (an ordinary `tester.pumpWidget` +
`tester.drag` on the same kind of `ListView` scrolls fine). Fixed —
`dispatchAtLocal` now holds a `HitTestResult` per pointer between `down`
and `up`, the same way the real binding does. This didn't fix
`Scrollable` — the offset stays 0.0 even after the fix — but it removed a
false lead: the cause isn't a stale hit test, it's deeper and wasn't found
within this session.

**Not done, honestly:**
- "the list scrolls under a finger" — the third acceptance point. The
  pointer mechanism is proven to deliver a full down/move/up sequence
  with a correct `delta` to a plain gesture recognizer
  (`onVerticalDragUpdate` reacts, the offset matches the computed one);
  `Scrollable` widgets (`ListView`, `SingleChildScrollView`) don't react
  at all to the same sequence — not one `ScrollNotification`, with no
  exception either. The cause wasn't found: not `GlobalKey` (`Scrollable`
  has none on this path), not `View.of` (no similar exception), not a
  stale hit test (checked and fixed separately, didn't help). This is an
  open question, not a rejected hypothesis — left named that way plainly,
  rather than presenting as finished something unproven.
- Semantics — per §7's own decision, wg-01 ships without it. Recorded:
  `flutter3d_session`'s own `CHANGELOG.md`, further in this same commit,
  names the gap explicitly.
- A cost measurement on a real phone (see `wg-00`'s own caveat above) — an
  emulator/simulator is still not a phone, `WidgetSurface` doesn't change
  that limit.
- A gizmo/highlight for a `widget_surface` entity in the editor itself — the
  new entity type passes `flutter3d_editor_core`'s own validation for
  free (an open type vocabulary, see `edu-00`), but no visual placeholder
  was added for it in the editor's own viewport — a separate, broader
  editor-UI task, not part of wg-01.

### wg-02: a terminal in the crypt and an operator panel — closed

Closed 2026-09-12. Both scenes are on a real `WidgetSurface` from wg-01,
not interactive in the sense of text or scrolling (both honestly don't
work — see `wg-01`), only tap and redraw-by-dirtiness, exactly what's
proven there.

**The terminal reuses an existing event stream, not a new hook.**
`apps/flutter3d_demo_dungeon`'s own `FrameEffects.say` already prints every
level message (doors, keys, `MechanismEvents.messages`) onto the HUD for
three seconds and forgets it; `FrameEffects.log` is the same call, the
same source, only a `ValueNotifier<List<String>>`, trimmed by
`logCapacity` (8 lines), rather than one forgotten line. `RunTerminal` is a
`StatelessWidget` with no `Scrollable`: it draws every log line at once
(bottom up), because `wg-01` already found that `Scrollable` widgets inside
a `WidgetSurfacePipeline` don't react to a synthetic pointer on a single
event — an honest boundary from there, not reopened here, only respected.

**A real finding, not anticipated in advance: the game level and the
editor check the document against DIFFERENT vocabularies.**
`flutter3d_editor_core`'s `vocabularyOf` accepts any `type` (an open
vocabulary — see `edu-00` §1), but `LevelValidator`, which the real game
loads through (`LevelLoader.build`), does not: an unknown type is an
ERROR, and `LevelLoader.load` throws, refusing to open the level at all.
Adding a `widget_surface` entity to `crypt.json` with no new `EntityKind`
registered in the game's own registry silently broke LOADING itself — not
only for the new code, but for all thirteen places in the
`apps/flutter3d_demo_dungeon` tree that build a `sampleRegistry()` for the
same file (eleven tests plus `main.dart`), caught by running the full test
suite, not one file. The fix — `WidgetSurfaceKind` in `flutter3d_bridge`
(the same `entityType` `WidgetSurfaceVisuals` already holds, spawning
nothing, exactly like `PlayerSpawnKind` is read as a coordinate rather
than spawning), and a new `extra` parameter on
`flutter3d_game_shooter`'s own `sampleRegistry()` — not a direct
dependency of the genre on `flutter3d_bridge`: the `flutter3d_game_shooter`
pubspec already explains why a genre package shouldn't know about the
bridge ("Only `bridge.dart` imports [flutter3d]... not a bridge's"), so
whoever adds a word only the bridge knows about is the application,
through `extra`, not the genre package through a new dependency.

**The operator panel — with no template to house it, honestly with a
dedicated test.** `tpl-04` doesn't exist, so `OperatorPanel`
(`apps/flutter3d_demo_dungeon/lib/src/operator_panel.dart`) isn't embedded
in any playable level at all — it's checked directly over edu-05's own
`SamplerDataSource`: a sine of the step, read into a `ValueNotifier<double>`,
fed into a real `WidgetSurface.tick()` (through `tester.runAsync` —
`wg-01`'s own finding about `currentImage()` and a real rasterization
pass, not `flutter_test`'s fake zone asynchrony). Twenty real samples
really move the panel — proven by `redrawCount` growing, not assumed.

Ten new tests: six in `run_terminal_test.dart`
(`FrameEffects.log` collects, drops `null`, trims from the start of the
list by capacity; `RunTerminal` — a placeholder on an empty log, shows
every line, redraws on a `ValueNotifier` change) and four in
`operator_panel_test.dart` (the widget itself shows and updates the value;
the full chain `SamplerDataSource` → `WidgetSurface.tick()` →
`redrawCount`). Plus two integration tests in `run_cubit_test.dart`: a
real `crypt.json` with a `widget_surface` entity resolves into a real
scene node through a passed-in `widgetRegistry` (the bridge, not the test,
builds the `WidgetSurface`), and an unregistered widget name reports a
problem, but doesn't crash the level — the same choice `FixtureVisuals`
already made for a model that failed to load.

Not done: the `tpl-02` gallery (neither scene is shown there — it hasn't
started itself and waits on net-03's own screen); the operator panel
isn't embedded in any twin template (`tpl-04` doesn't exist); a real
phone for a cost measurement (the same caveat as `wg-00`/`wg-01`).

### tpl-04: non-game templates — three levels, not three separate applications

Closed 2026-09-12, under the same limitation already named by
`ai-01`/`par-03`/`edu-05`: the literal `--list`/`init` (`ap-10`) doesn't
exist, and "in the gallery" waits on `tpl-02`, which doesn't exist either.
Three templates are built and proven with real tests, as levels, not
stubs.

**Three separate `.json` files, not three Flutter applications.** `ap-10`,
which would lay them out as separate projects with their own
`pubspec.yaml`, doesn't exist, and hand-building three copies of
`apps/flutter3d_template_app` for the sake of a difference of one level
would breed exactly the duplication
`flutter3d_template_app`'s own doc comment already warns against.
Instead: `apps/flutter3d_template_app/assets/levels/viewer.json`,
`configurator.json`, `twin.json` — three documents over the same open
`LevelCubit`, which already accepts any level via
`--dart-define=level=`.

**All three use only `widget_surface`, nothing beyond what `wg-01`/`edu-05`
already proved.** `edu_annotation`'s own `attachTo`/`offset` — relative
widget positioning — got no bridge anywhere in this session (neither at
`edu-01`, nor here): `Editing`/MCP can place and edit such an entity as
data, but no render path reads `attachTo` and turns it into a
`WidgetSurface` position. The three templates therefore position a panel
directly through `at`/`yaw`, which `widget_surface` already carries as an
ordinary entity — an honest boundary, not a corner cut: tpl-04's own
wording asks for three templates, not a second bridge.

- **The viewer** (`viewer.json`) — `edu_sequence`/`edu_step` with three
  captioned views and a `widget_surface` "view-caption" on the wall.
- **The configurator** (`configurator.json`) — one `widget_surface`
  "configurator-panel"; a tap switches between three product variants
  (name and price) — **on the panel's own state, not on the product's
  mesh**: `Brush` carries no `name`
  (`packages/flutter3d_sim/lib/src/level/brush.dart`), so there's no way
  to address "this specific box" in `scene.meshes`, the way a
  `widget_surface` node already can. Retinting the real geometry is
  honestly not done.
- **The twin** (`twin.json`) — an `edu_data_source` (`kind: sampler`) and
  an `edu_step` with `bindings`, read by edu-05's own `resolveBindings`
  every frame into a `widget_surface` "twin-dashboard."

**A real finding along the way, not in this code: not one application in
this session had, until now, aimed a pointer at a `WidgetSurface` through
a real tap, only a manually assembled ray in a test.**
`LevelScreen._tapWidgetSurface` is the first live path:
`Raycaster.setFromScreen` (the scene, not `CollisionWorld` — a widget
surface is a mesh node, not a physical collider) finds the mesh under the
finger, `WidgetSurface.uvAt` converts the hit into a UV, `dispatchAtUv`
delivers a synthetic tap — the same chain
`widget_surface_visuals_test.dart` already proved by hand with a
manually-built ray, here assembled from a real `PointerDownEvent` for the
first time. Only a whole tap is handled (down+up together): `wg-01`'s own
finding about a broken `Scrollable` through this same path already said a
drag isn't worth delivering here.

Seventeen new tests: ten in `test/tpl04_levels_test.dart` (all three
levels open through the application's own open registry with no
exceptions; `stepCaptions`/`stepWithBindings` — new public functions in
`main.dart` — read `edu_sequence`/`edu_step` from a real, flat, no-wrapper
document; an empty widget registry honestly names a missing name, rather
than silently losing the entity; `resolveBindings` on a real twin step
gives different numbers at different steps) and seven in
`test/template_widgets_test.dart` (the viewer's own step switching
forward and wrapping backward; a tap on the configurator changes both the
widget and the controller; the twin panel shows a placeholder before the
first value and a real number after). All twenty of the package's tests —
together with the ones that already existed — are green.

Not done: the literal `--list`/`init` (`ap-10`); the templates appearing
in the gallery (`tpl-02` hasn't started); the bridge for
`edu_annotation.attachTo`/`offset` into rendering (see above); retinting
the product's own geometry on the configurator; a measurement on a real
phone.

---




