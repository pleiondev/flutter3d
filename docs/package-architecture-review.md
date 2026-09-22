# flutter3d package architecture review

Date: 2026-09-15. Branch `template-layers`, from `origin/main` (`004468e1`).
A follow-up to `doc/package-merge-plan.md` of 2026-09-13, which answered the
same question ("is forty-five packages too many?") and kept 38. This document
covers why that was not enough, what changed in two days, and what the map
should look like.

What prompted it: a read of `apps/flutter3d_template_app` showed that the
seed of a new project carries a digital twin, a configurator and a guided
tour, plus half of a game's assembly that packages already partly hold. The
owner's question: "if we have `flutter3d_app` and `flutter3d_game`, why do we
need a template, and what is in it?" — and behind it a broader one: too many
abstractions and too many packages.

## 0. In short

1. **45 packages and 10 applications; about 30 packages and 6 applications
   can be honestly justified** (after the owner's decisions — 35 and 9, §8).
   The excess is not a scatter of small packages but three systemic causes:
   vertical products inside the engine repository, one application layer cut
   into four packages, and boundaries that outlived their reasons.
2. **Verticals don't belong to the engine.** `flutter3d_twin`,
   `flutter3d_lab`, `flutter3d_stereo`, three lesson applications and the
   non-game `tpl-04` templates (viewer, configurator, twin) are products built
   on the engine. Their vocabulary has already leaked into shared packages:
   `edu-05` data sources in `flutter3d_sim`, `lesson_player.dart` in
   `flutter3d_bridge`, `lesson_authoring.dart` in `flutter3d_editor_core`, and
   `flutter3d_twin` in the `pubspec.yaml` of every project the editor creates.
3. **The application layer is one layer with four packages.**
   `flutter3d_game` (input plus a re-export of `sim`), `flutter3d_session`
   (surface, run, screens), `flutter3d_bridge` (level → scene) and
   `flutter3d_app` (backend choice plus a re-export of three packages). Every
   application imports all of them; the genre packages take only the
   re-exported `sim` from `flutter3d_game` — not a single symbol from its
   Flutter half.
4. **Three barrel re-exports hide the real graph.** `flutter3d` re-exports
   four packages, `flutter3d_game` re-exports `flutter3d_sim`, `flutter3d_app`
   re-exports three. The graph in the pubspecs looks layered, while a consumer
   gets everything with one import line; the boundaries are invisible exactly
   where they get crossed.
5. **Abstractions in code are not the main problem.** The scan found about
   twenty interfaces with a single implementation across the whole
   repository, and nearly all of them are test seams or genre-neutral hooks.
   The redundancy lives at the level of packages and re-exports, not classes.
6. **The template does not need to be an application.** The minimal template
   is the `example/` of the universal `flutter3d_app`; the game template is
   the `example/` of `flutter3d_game`. On top of that, judging by the code,
   today's template breaks the projects the editor creates (§6).
7. **Publishing on pub.dev is not an argument right now.** 22 packages went
   up on 2026-09-08 at 0.6.0; none has a like except `flutter3d` (6). Before
   1.0, renaming and `discontinued` are cheap; after it they are expensive.

## 1. Method

Against the `origin/main` tree, with scripts rather than from memory:

- a graph of every `pubspec.yaml` under `packages/` and `apps/`: internal
  dependencies in both directions, dev dependencies, `lib/` line counts, test
  counts, Flutter or flat;
- imports: how many files in other members' `lib/` import a package directly,
  and who goes around a re-export;
- an abstraction scan: `abstract`/`interface`/`sealed` classes and how many
  classes extend or implement each (a regex heuristic — orders of magnitude,
  not an exact count);
- the pub.dev API: whether a package is published, at which version, likes
  and downloads.

Checked against `ARCHITECTURE.md` §3, `tool/structure/repository.dart`
(`flatDartPackages`, `genrePackages`, `applications`) and the six boundary
criteria in `doc/package-merge-plan.md` §1.

## 2. What the tree holds today

| Group | Packages | `lib/` lines |
|---|---|---|
| Graphics contract and backends | `hardware`, `impeller`, `webgl`, `webgpu`, `cpu`, `conformance`, `shaders` | ≈54,000 |
| Engine | `flutter3d` (shell, 1,084), `core` (23,022), `geometry` (3,141), `formats` (17,330), `samples`, `particles` (488), `particles_core` (1,826), `testing` (333) | ≈47,000 |
| Simulation | `physics` (5,686), `sim` (16,024), `net` (610), `net_webrtc` (173) | ≈22,500 |
| Game application layer | `game` (1,893), `session` (4,419), `bridge` (2,383), `app` (379), `audio` (1,469), `pad_input` (1,407), `pointer_lock` (499) | ≈12,400 |
| Genres | `game_shooter`, `game_platformer`, `game_racing`, `game_strategy` | ≈18,800 |
| Level editor | `editor_core` (2,825), `editor_mcp` (668), `mcp_kit` (373), `build` (1,084) | ≈4,900 |
| Modeller | `mesh` (16,251), `model_core` (21,166), `model_mcp` (4,221), `rig` (1,518), `fbx` (76), `render_job` (573) | ≈43,800 |
| Agents over a game | `sim_mcp` (699), `render_mcp` (540) | ≈1,200 |
| Verticals | `twin` (85), `lab` (296), `stereo` (930) | ≈1,300 |

Applications: four demos, the level editor, the modeller, the template, two
lesson viewers (plain and stereo), and the pendulum lab.

22 packages are published on pub.dev (all at 0.6.0 from 2026-09-08, many
already at 0.7.0 in the tree); 23 were never published, including every
modeller package, `core`, `geometry`, `formats`, `game_strategy`, `twin`,
`lab` and `stereo`.

## 3. Why the previous review was not enough

`doc/package-merge-plan.md` checked each package against six reasons for a
boundary and kept any package that passed at least one. The reasons are
sound, but the way they were applied missed three things.

**The boundary was checked per package, not per layer.** "Needs the Flutter
SDK" is a legitimate boundary between `sim` and `game`. It does not explain
why the Flutter side of one and the same layer — input, surface, screens, the
run, loading a level into a scene, choosing a backend — is spread across four
packages. Each of the four has its own plausible reason; together they
describe one application.

**The seventh reason, "a narrow subject domain", justified verticals.**
`flutter3d_lab` was kept as a separate package "on the same grounds as the
genres". A genre is the kind of game the engine's game layer exists for. A
lab exercise, a digital twin and a stereo lesson are products for a different
audience, and a separate package inside the engine repository does not
isolate them: their vocabulary still ended up in `sim`, `bridge`,
`editor_core` and the template.

**Reasons were not re-checked after moves.** In two days
`mcp-01n`/`mcp-02n`/`mcp-03n` made `hardware`, `cpu` and `core` flat. After
that:

- `flutter3d_render_job` exists because "nothing that renders can be plain
  Dart" (its `pubspec.yaml`) — no longer true: `flutter3d_model_core` renders
  on its own through the flat `core` in `render_project.dart`, and
  `render_job` still has zero importers;
- `flutter3d_bridge/pubspec.yaml` says `flutter3d_game` depends "only on
  flutter, pointer_lock and vector_math" and that `bridge` is "the one package
  allowed to depend on both"; in fact `game` also depends on `pad_input` and
  `sim`, `session` also stands on both sides (`flutter3d` and `game`), and
  `bridge` depends on `session` for a single `WidgetSurface`;
- `ARCHITECTURE.md` §3 says "forty-six packages and seven applications"; the
  tree has 45 and 10, and the §3.2 table lacks `net`, `net_webrtc` and
  `stereo`;
- of the merge plan's seven steps, three were done (`backend`, `screens`,
  `cloth`); `fbx`, `rig` and `render_mcp` are still there, and `render_job`
  has no consumer.

## 4. Findings by group

### 4.1 Verticals

| What | Where | Consumers |
|---|---|---|
| `flutter3d_twin` | a package, 85 lines: a spindle temperature sine and a source registry | the template only; through `pubspecFor`, every created project |
| viewer, configurator, twin (`tpl-04`) | `apps/flutter3d_template_app`: `template_widgets.dart`, `operator_panel.dart`, three levels, ~200 lines of `main.dart` | the template and, through `make_templates.py`, the editor's four game templates |
| `flutter3d_lab` + `apps/flutter3d_lab_pendulum` | a 296-line package, a 441-line application | each other |
| `flutter3d_stereo` + `apps/flutter3d_stereo_lesson_viewer` | a 930-line Android plugin | that application only |
| `apps/flutter3d_lesson_viewer` | 938 lines | — |
| lesson vocabulary in shared packages | `sim/level/data_source.dart` and `save/data_source_trace.dart` (239), `bridge/lesson_player.dart` (90), `editor_core/lesson_authoring.dart` and `binding_lookup.dart` (172) | the lesson applications and the template |
| `flutter3d_net_webrtc` | a 173-line plugin | none |

Recommendation: the digital twin, the configurator and the tour move to
wherever the owner already keeps a digital-twin project; lessons, the lab and
stereo move to a separate product repository that depends on the published
engine packages (or are deleted if the product isn't needed — the owner's
call). `net_webrtc` is deleted until it has a consumer. A guard for the
future: a rule in `tool/structure.dart` forbidding lesson and twin vocabulary
in engine packages, modelled on the genre rule.

**Accepted differently (§8):** only the twin, the configurator and the tour
leave; lessons stay, and so does `net_webrtc`.

`WidgetSurface` (a widget on a surface in 3D) stays regardless: the dungeon
terminal uses it (`wg-02`) — it is an engine capability, not a lesson one.

### 4.2 The application layer — two packages by meaning

Today: `game` (Flutter: touch, keyboard, gamepad, accommodations,
diagnostics; re-exports all of `sim`) → `session` (surface, `RunSession`,
screens, storage, `WidgetSurface`) → `bridge` (level → scene, actor and
fixture visuals) and `app` (backend choice, re-exports `session`, `pad_input`,
`pointer_lock`).

Verified:

- genre packages use no symbol from `game`'s Flutter half (`DesktopInput`,
  `TouchControls`, `GameConfig`, `Accommodations`, `Issues`, `PadActions`,
  `Playing`); only three `hud.dart` files in them import Flutter;
- `game` is imported by 147 files, almost all of them for the re-exported
  `sim`;
- `bridge` depends on `session` for one file, `widget_surface_visuals.dart`;
- all ten applications except the editor depend on `app` and on two or three
  of the packages below it at once.

The first version of this section proposed `game` + `session` + `bridge` →
`flutter3d_app`. The owner rejected it, and rightly: the engine is meant to be
universal, game components belong in `flutter3d_game`, and that merge would
have put them into a package the modeller, the editor and the lessons use.
What those applications take from the layer today:

- the modeller — `openDevice`, `presentFrame`, `SceneSurface`,
  `Storage`/`BinaryStorage`, `FrameTimingLog`;
- the lessons and the lab — `SceneSurface`, `openDevice`, `DidNotStart`,
  `WidgetSurface`, `LevelLoader`;
- the level editor — the same, plus `GameAction`/`DesktopInput` for its fly
  camera: it is an editor of game levels.

Verdict (accepted):

- **`flutter3d_app` is the universal layer** for any Flutter application on
  the engine: backend choice, `SceneSurface`, `FrameClock`, `FrameTimingLog`,
  `DidNotStart`, the bug report, storage, `WidgetSurface` with its pipeline
  and `WidgetSurfaceVisuals`, and loading a level into a scene
  (`LevelLoader`, `SharedMeshes`, `SurfaceMesh`, `VisibilityCuller`). It
  depends on the flat `sim` for the level format.
- **`flutter3d_game` holds everything game-specific**: input (touch,
  keyboard, gamepad, bindings), `RunSession` and the run timeline, game
  screens (settings, rebinding, volume, saves, credits, automap, restart),
  actor and fixture visuals, sound occlusion, and the "walk around a level"
  base that is written inside the template today. It stands on `app`, `sim`,
  `flutter3d`, `audio` and `particles`. Its re-export of all of `sim` goes
  (§0, item 4).
- `session` is split between these two packages; `bridge` moves into `game`,
  except for level loading; `lesson_player.dart` moves to the lessons.
- Genre packages: the main library stands on the flat `flutter3d_sim`,
  `bridge.dart` on `flutter3d_game` (three genres already have one, the
  platformer gets one), and the HUD goes into `bridge.dart`. The "the
  simulation names no Flutter" rule extends to a genre's main library.
- `audio`, `pad_input` and `pointer_lock` stay separate: they are plugins
  with native code and clear standalone names.

Cost: `app` gains the flat `sim` and `physics` in its graph (no third-party
dependencies); the published `session` and `bridge` go `discontinued` with
`replaced_by`; `game` keeps its name and changes its contents.

### 4.3 The flat core — `geometry` and `formats` into `core`

`flutter3d_geometry`, `flutter3d_formats` and `flutter3d_core` are all flat,
none is published, and each has a single third-party dependency,
`vector_math`. The split was justified by consumers that want one part
without the rest: `mesh` takes `geometry` without the decoders, `editor_core`
takes `formats` without the renderer. But a flat package imposes neither
Flutter nor foreign libraries on a consumer — only compile time, which tree
shaking removes. None of the six boundary reasons applies here.

Verdict (accepted): `geometry` + `formats` → `flutter3d_core`; `flutter3d`
stays a thin Flutter shell and re-exports two packages (`core`, `hardware`)
instead of four. `fbx` goes wherever `formats` goes.

### 4.4 The modeller — one document package

`flutter3d_rig` (1,518 lines, flat, unpublished) — consumed by `model_core`
and `model_mcp`. `flutter3d_fbx` — 76 lines that refuse to read FBX.
`flutter3d_render_job` — zero importers and a reason that stopped being true
(§3). `flutter3d_mesh` — the editable half-edge mesh; outside the modeller
only dev tests of `flutter3d` and `cpu` and a bench use it.

Recommendation: `rig` and `render_job` → `model_core` (tiling with SSAA
merges with `render_project.dart`, leaving no second project-to-scene
converter); `fbx` → `core` (§4.3). `mesh` → `model_core` was recommended with
less confidence: 16 thousand lines of a self-contained data structure with its
own AOT bench are an argument for a separate package, should a game ever need
the mesh.

**Accepted (§8):** `rig` and `render_job` into `model_core`; `mesh` stays a
separate package. The modeller ends up with `mesh` + `model_core` +
`model_mcp`.

### 4.5 MCP — three servers, one kit

`render_mcp` → `sim_mcp`, as decided on 2026-09-13 and not done: one
dependency closure, one agent. `mcp_kit` stays: flat servers (`editor_mcp`,
`model_mcp`) and a Flutter server (`sim_mcp`) both use it.

### 4.6 Particles — one flat package

`flutter3d_particles` imports Flutter for a single `debugPrint` and
`flutter3d` for the re-exported core. After §4.3 it can become flat and absorb
`particles_core`; `model_core` then depends on `flutter3d_particles`
directly. The published name stays; `particles_core` was never published.
Folding it into the engine itself — no: "the engine names no particles" is a
test of the extension model, and a useful one.

### 4.7 What stays, and why

| Package | Held up by |
|---|---|
| `hardware`, `impeller`, `webgl`, `webgpu`, `cpu` | the contract and the backends: native code, `web`, WGSL |
| `conformance`, `shaders` | the backend test suite; GLSL shared by three backends |
| `flutter3d` + `core` | the Flutter SDK boundary: `rootBundle`, `dart:ui` versus `dart run` |
| `samples` | 4.7 MB of assets a game doesn't need |
| `testing` | `flutter_test` |
| `physics`, `sim` | flat: a server replays a run without Flutter |
| `net` | `web_socket_channel`, which the simulation doesn't need |
| `audio`, `pad_input`, `pointer_lock` | plugins with native code |
| the four genres | the genre rule |
| `editor_core`, `editor_mcp`, `mcp_kit`, `build` | flat tools and the build hook |
| `mesh`, `model_core`, `model_mcp`, `sim_mcp` | the modeller's mesh and document, and agent servers with different closures |

## 5. Abstractions in code

A heuristic scan over the `lib/` of every package and application:

- interfaces and abstract classes with **one** implementation — about twenty
  across the whole repository: `RenderServices→Renderer`,
  `FrameGraphNode→RenderNode`, `PassEncoder→CommandEncoder`,
  `TimelineClient→VmServiceTimelineClient`, `HeadTracker→SensorHeadTracker`,
  `HeadlessGame→ShooterHeadlessGame`, `ActorAppearance→DungeonMonsters`, the
  platformer runner's three interfaces, and a few more. Nearly all are test
  seams (replaced in tests) or hooks that keep a shared package from naming a
  genre. Removing them would cost testability;
- "abstractions with no implementations" are mostly `abstract final class`
  used as a namespace for constants (`CollisionLayers`, `EntityTypes`,
  `VkFormat`) — a Dart idiom, not an extra layer;
- the real surplus indirection is the re-exports (§0, item 4) and thin
  packages that exist for one file: `app` for backend choice, `fbx` for a
  refusal, `twin` for a sine wave.

Separately from the package review: doc comments narrate the history of
decisions ("moved here because…", "used to be…"), and in some pubspecs they
have drifted from the code (§3). That is not an abstraction, but it makes
boundaries heavier than they are: to reconsider a package, one has to argue
with a paragraph.

## 6. The template

`apps/flutter3d_template_app/lib/main.dart` is 624 lines, of which:

- about 60 connect to the engine: `openDevice`, `Renderer`, `SceneSurface`,
  the "did not start" screen, loading;
- about 300 are game assembly: `LevelCubit`, `OpenKind`, collisions, spawn,
  `CharacterController`, walking, jumping and sprinting, mouse look, the
  controls hint;
- about 200 are `tpl-04`: tour captions, configurator variants, bindings and
  the twin's reading, tapping a `widget_surface`.

`tool/make_templates.py` copies this file as text into the shooter,
platformer, racing and strategy templates; `pubspecFor`
(`packages/flutter3d_editor_core/lib/src/scaffold_templates.dart:45-49`) adds
`flutter3d_twin` to every new project. The file imports
`src/template_widgets.dart`, which the templates' `index.json` never writes —
**judging by the code**, a project the editor creates does not compile (not
verified by a build; `scaffold_test` compares package imports against the
pubspec and does not see relative imports).

The game parts ended up in the template because from day one it was the seed
of a project for the level editor (`tpl-01`: "the four demos become
templates"), and the "level + body + look + input" assembly had no package:
the loader lived in `bridge`, the body controller in `physics`, input in
`game`, the surface in `session`.

Verdict: the template application goes. The minimal template is the
`example/` of `flutter3d_app` (a lit cube with orbit); the game template is
the `example/` of `flutter3d_game` (a level, a body, look, input). CI builds
both, `make_templates.py` copies them, and `scaffold_test` builds the created
project as a whole instead of comparing strings.

## 7. Target map

The review's recommendation and what was accepted (§8):

| Today | Recommended | Accepted | Δ |
|---|---|---|---|
| `twin` and the `tpl-04` templates | out of the repository | out of the repository | −1 |
| `lab`, `stereo`, lesson applications | out of the repository | **stay** | 0 |
| `net_webrtc` | delete | **stays**: it will have a consumer | 0 |
| `game`, `session`, `bridge`, `app` | `flutter3d_app` | **`flutter3d_app` (universal) + `flutter3d_game` (game)** | −2 |
| `geometry`, `formats`, `fbx`, `core` | `flutter3d_core` | `flutter3d_core` | −3 |
| `rig`, `render_job`, `model_core` | `flutter3d_model_core` | `flutter3d_model_core` | −2 |
| `mesh` | into `model_core` | **stays** | 0 |
| `particles_core`, `particles` | `flutter3d_particles` (flat) | the same | −1 |
| `render_mcp`, `sim_mcp` | `flutter3d_sim_mcp` | the same | −1 |
| **45 packages, 10 applications** | **30 and 6** | **35 packages, 9 applications** | **−10, −1** |

Applications after the decisions: four demos, the editor, the modeller, two
lesson viewers and the lab; the templates become examples of `flutter3d_app`
and `flutter3d_game`.

## 8. Owner decisions, 2026-09-15

1. **Verticals.** The digital twin, the configurator and the tour (`tpl-04`,
   `flutter3d_twin`) leave the engine repository: the owner has a separate
   Dart project for the digital-twin model. Lessons stay — `flutter3d_lab`,
   `flutter3d_stereo`, `flutter3d_lesson_viewer`,
   `flutter3d_stereo_lesson_viewer`, `flutter3d_lab_pendulum` and their
   vocabulary in `sim`, `bridge` and `editor_core`. Open during
   implementation: the `edu-05` data sources in `sim` (`data_source.dart`,
   `data_source_trace.dart`) stay if the lessons use them, and leave with the
   twin if only the twin does.
2. **The application layer is two packages by meaning, not one.**
   `flutter3d_app` holds what is universal for any application on the engine,
   including loading a level into a scene; `flutter3d_game` holds everything
   game-specific, including the "walk around a level" base from the template
   (§4.2). Genres stand on the flat `sim`, with the HUD in the genre's
   `bridge.dart`; the templates are examples of the two packages. At first
   "four packages into `flutter3d_app`" was accepted — the owner revised it
   the same day, because game components belong in `game` and the engine
   stays universal. Two earlier decisions from the same session are revoked
   as well: "the shared game base is a new package above `bridge`" (that is
   `flutter3d_game`) and "non-game add-ons are a package with a Flutter layer"
   (they leave the repository).
3. **Core and tools.** Accepted: `geometry` + `formats` + `fbx` → `core`,
   `rig` + `render_job` → `model_core`, `particles_core` → `particles`,
   `render_mcp` → `sim_mcp`. Not accepted: `mesh` → `model_core` (`mesh`
   stays separate) and deleting `net_webrtc` (it will be used).
4. **pub.dev.** Before 1.0, published names may freely go `discontinued`
   with `replaced_by`; everything ships in one 0.7.0 release.

## 9. Order of work

1. **No publishing, days.** Remove `tpl-04` and `flutter3d_twin` from the
   template, `pubspecFor`, `tool/make_templates.py` and the tree; make the
   created project compile and teach `scaffold_test` to check it; merge `rig`
   and `render_job` → `model_core`, and `render_mcp` → `sim_mcp`.
2. **The flat core.** `geometry` + `formats` + `fbx` → `core`,
   `particles_core` → `particles`.
3. **The application layer.** Split `session` between `app` (universal) and
   `game` (game-specific), move `bridge` into `game` and level loading into
   `app`; the "walk around a level" base from the template goes into `game`;
   genres' main libraries onto `sim`, the HUD into `bridge.dart`; the
   templates become the `example/` of the two packages.
4. **Documents and publishing.** `ARCHITECTURE.md` §3, the README,
   `tool/structure.dart` rules, counters; a 0.7.0 release with `discontinued`
   and `replaced_by` for the retired names — in one release, as the previous
   plan proposed.
