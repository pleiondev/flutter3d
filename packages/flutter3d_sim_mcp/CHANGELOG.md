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
