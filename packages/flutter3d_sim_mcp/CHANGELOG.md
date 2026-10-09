## 1.0.0-rc.1

- **Breaking: `PictureAnswer` is not re-exported.** It is the agent kit's,
  `package:flutter3d_mcp/kit.dart`.

- **Depends on `flutter3d_foundation` instead of the plugin API**, for the
  exception family a reading predicate's refusal is of.

- **`run.bisect` steps each run through a `RunLoop`**, rewinding by the
  loop's captures rather than by the run's own save and restore. A layout
  names the same entities and components; a path with no layout starts
  with the run's part, `run.data.`.
- **The simulation and diagnostics servers announce schema version 1.0.0**,
  the first stable release's.
- **The tests written against the unpublished demo content moved to
  `flutter3d_demo_content`**; no dev dependency on it any more, so pana
  resolves the package.

- **Built on `flutter3d_mcp`'s kit.** The kit every server shares is the
  `kit.dart` library of `flutter3d_mcp` now, not the `flutter3d_mcp_kit`
  package, and `PictureAnswer` is re-exported from there. This package
  stays apart from the other servers because it plays a game, which takes
  the Flutter SDK, and theirs may not.
- **Tools are named `area.verb`, and the old names still answer.** The
  simulation's server (`flutter3d.sim`, schema 1.1.0) offers `level.open`,
  `run.step`, `state.snapshot`, `run.write` and the rest from `simToolNames`;
  the diagnostics server (`flutter3d.diagnostics`, schema 1.1.0) offers
  `render.frame`, `render.pixel`, `render.passes`, `render.scanNan` from
  `diagnosticToolNames`. `open`, `step`, `writeRun`, `scanNaN` and the rest
  stay aliases until 2.0. Each tool says whether it only reads.
- **Breaking:** `ReadingPredicateException` extends `Flutter3dFormatException`
  instead of implementing `Exception` directly. The name and members are
  unchanged and every `on` clause that caught it still does; every exception
  the engine throws now hangs from `Flutter3dException` in
  `flutter3d_plugin_api`, in one of four families: format, capability, plugin
  and resource. A caller who reports anything the engine refused catches the
  root; one who acts on a kind catches its family. The migration table marks
  it as nothing to do.
- **1.0.0 is a promise: strict semver from there.** This release candidate
  already keeps it. A patch fixes bugs and
  breaks nothing, a minor adds, and a break waits for a major. The whole
  public API is stable, with no experimental exceptions, and is held to the
  snapshot in `api/`. A deprecated name stays until the next major and for
  at least six months, and says what replaces it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#the-api-is-a-snapshot)
  has the rules, and
  [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)
  says which releases get fixes and on which platforms.

- **An `order` verb for games played by orders.** It is offered only when the
  session's game is an `OrderedGame`. It gives one order through the input
  and steps on, so the runs it writes verify and bisect like any other. The
  launcher plays any of the four genres, and the server takes the installed
  plugins' `McpTools` as `projectTools`.

- **The project's plugin tools are offered beside the server's own.**
  `SimMcpServer` and `DiagnosticMcpServer` take an optional
  `projectTools`, the project's `McpTools` from `flutter3d_mcp_kit`, and
  `onProjectCall` to watch calls to them. Each plugin tool is listed as
  `<plugin id>.<name>` after the server's own, and the list follows plugins
  as they are switched on and off. A server built without it offers exactly
  what `api/flutter3d_sim_mcp.mcp` lists, so the schema versions do not
  move. An addition.

- **`verify` refuses a run from another simulation before playing it**, when
  the game says its number (`VersionedSimulation`). The reason names both
  numbers and mentions the run's pose record. `writeRun` and `expect` write
  the game's simulation into the run.

- **The tools are a contract too.** Both servers' tool names and input
  schemas are written down in `api/flutter3d_sim_mcp.mcp` — read from
  source, with the game's own name and buttons shown as `{game}` and
  `{button}` — and held to the same semver as the Dart API: a tool removed or
  renamed without an alias, or a new required argument, waits for a major.
  Each server announces its own number as `schemaVersion` in its
  `initialize` result, `simMcpSchemaVersion` and `renderMcpSchemaVersion`
  (both 1.0.0), and each moves only when its tools do.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#tools-for-agents-are-a-contract-too)
  has the rules.

- **`bisect` finds where two runs part.** It reports the step, whether
  the input differed there, and the first field that differs, using the
  library's `bisectTapes`.

- **`bisect` names the entity and the component two runs part on.** Given
  where the save keeps its entities, as `entities: {"ecs": ["entities"]}`
  or `{"rows": "actors"}`, or by the host through `SimSession(entities:)`,
  the answer lists every component that differs at that step and starts
  the path in the first of them (`0.facing.yaw`). A step where the runs
  part outside the entities says that no component differs there.

- **The session runs on the physics core.** A run is verified on the
  backend it was recorded on, and the session returns to its own backend
  afterwards. Playtests run each isolate on the session's backend.

- **`verify` refuses a run with the level edited under it**, naming the
  step. The swapped level is built by the game that recorded the run, and a
  session over a bare simulation would answer with a divergence it did not
  cause.
- `Playtest.heatmap` bins through `flutter3d_sim`'s `Heatmap`, and `verify`
  replays through `resimulate`, so a playtest report and a telemetry heatmap
  are one format and a run this server calls verified is one a telemetry
  server would take. Answers and JSON are unchanged.

Its `flutter3d_*` dependencies ask for `^1.0.0`.

## 0.8.0

**An agent's claim about a run comes with the run that proves it.** The
playing server has two new tools, eight in all. `expect` steps the open run
holding one intent until a predicate holds or `limit` steps pass, then writes
the run so far to `path` as a `.f3drun` and answers with the step and the
state digest there. If the file cannot be written it refuses, naming the step
and the digest, since the claim would have nothing behind it. If the subject
leaves the reading mid-run, as it can in a game that removes what it kills,
it stops there, writes what it has and says who went missing. `verify`
replays a `.f3drun` into a fresh run of its own level, apart from the
session's, checks the level hash and the starting state, and reports where
the digests first part or that they agree, with an optional predicate checked
where the replay ends.

**The predicates read only what every game's reading shares.**
`ReadingPredicate.fromJson` reads `NearPredicate`, `InsidePredicate`,
`AlivePredicate` and `HealthPredicate` over the `player` row or an actor by
name, so the server stays free of any genre; a claim it cannot read throws
`ReadingPredicateException`. Contacts are left out, and both tool
descriptions say why: game events are not saved in a run, so no replay could
back a claim about them.

`simMcpVersion` and `renderMcpVersion` are `'0.8.0'`.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**Released with the rest of the stack at 0.7.1.** Nothing in this package
changed. The release it resolves against builds from pub.dev again and no
longer crashes Metal on the first unlit draw.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3.

## 0.7.0

**The first publication.** The 0.6.0 below was a number carried inside the
workspace and never reached pub.dev. 0.7.0 is the number the whole shelf goes
out on, so one number names one tree and `^0.7.0` on any `flutter3d_*` package
resolves against every other; `doc/boundary-0.7.0.md` lists the thirteen
packages that begin here. The package needs the Flutter SDK, because `frame`
draws the level through `flutter3d` over `flutter3d_cpu` and that needs
`dart:ui`. It has no `bin/`: a host runs a server inside `flutter test` and
hands it a `Socket`, since `flutter test` prefixes every line written to
stdout and a protocol framed by lines does not survive that.

**Accepted `flutter3d_render_mcp`: one package, two servers.** The diagnostic
server — a headless frame in one of the renderer's debug views, one pixel read
back unclamped, the passes the frame graph ran, a scan for the first NaN
(`par-02`) — lives beside the playing one as `DiagnosticMcpServer`, with
`DiagnosticRenderer` drawing both. The two packages already had the same
dependency closure, and `SimRenderer.frame()` was already the diagnostic
renderer's `lit` view. `flutter3d_render_mcp` was never published. Neither
server's tools changed.

**The playing server names no genre.** `SimSession(game:)` and
`Playtest(game:)` take a `HeadlessGame` from `flutter3d_sim`, and
`SimMcpServer` builds its tools and its instructions from that game's `name`
and `buttons`, so an agent reads the words of the game it is handed. The
0.6.0 in this workspace imported `flutter3d_game_shooter` and called its
player, its inventory and its fire button. The shooter is a dev dependency
now, where the suite plays the shipped crypt as `ShooterHeadlessGame`, and
`staging.dart`, this package's copy of the demo's composition, is gone: the
composition is `flutter3d_game_shooter`'s. The six tools are still `open`,
`step`, `snapshot`, `digest`, `writeRun` and `frame`, and `writeRun` writes a
`.f3drun`.

**`SimRenderer.open` and `DiagnosticRenderer.open` require the
`EntityRegistry`.** Both load the level through `LevelLoader` with
`sidecars: false`, and a level naming an entity type the registry does not
know is refused, so a level with a `widget_surface` in it draws once the host
registers `WidgetSurfaceKind`. A frame is 320 by 200 on the software
rasteriser.

**`passes` reports what each pass cost.** Every entry carries the pass's `name`
and `active` with `micros`, `drawCalls`, `triangles` and `pipelineSwitches`,
read from `FrameResult.passes` of the frame `frame` last drew. `pixel` and
`scanNaN` read that same frame as unclamped floats, and the four views are
`lit`, `normals`, `shadowMap` and `staticShadowMap`. `DiagnosticView` is an enum, and its four values are the
debug outputs `RenderSettings` has.

**The servers report the package's version.** `simMcpVersion` and
`renderMcpVersion` are `0.7.0`. They said 0.1.0 while the pubspec moved, and a
test holds them to the pubspec now.

**What it depends on.** `flutter3d_sim`, `flutter3d`, `flutter3d_app`,
`flutter3d_cpu` and `flutter3d_mcp_kit` at `^0.7.0`, `vector_math` and
`dart_mcp` from 0.5.2 up to 0.6.0. `PictureAnswer` is re-exported from
`flutter3d_mcp_kit`.

## 0.6.0

* **`ai-00`: an agent plays a shooter level blind.** `open`/`step`/
  `snapshot`/`digest`/`writeRun`/`frame` — six tools over a socket, MCP's own
  `stdioChannel` given a `Socket` instead of literal stdio, because `flutter
  test` rewrites stdout through its own logger and a protocol tied to an
  exact line format does not survive that.
* **`ai-01`: batch playtesting.** `Playtest.run` — one `Isolate.run` per
  playthrough, a random policy that holds direction and aim for tens of
  steps at a time, four outcomes (`died`/`exited`/`stuck`/`timedOut`) tied to
  the simulation's own state plus a stuck heuristic, and `Playtest.heatmap()`
  — cell density, death points, an outcome count, as the JSON `ai-02`'s
  editor layer reads back.
