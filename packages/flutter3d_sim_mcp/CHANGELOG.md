## Unreleased

**Accepted `flutter3d_render_mcp`: one package, two servers.** The diagnostic
server — a headless frame in one of the renderer's debug views, one pixel read
back unclamped, the passes the frame graph ran, a scan for the first NaN
(`par-02`) — lives beside the playing one as `DiagnosticMcpServer`, with
`DiagnosticRenderer` drawing both. The two packages already had the same
dependency closure, and `SimRenderer.frame()` was already the diagnostic
renderer's `lit` view. `flutter3d_render_mcp` was never published. Neither
server's tools changed.

## 0.7.0

**`staging.dart`'s composition moved to `flutter3d_game_shooter`'s own
`sample.dart`, and this package's own files stopped importing the shooter's
vocabulary wholesale.** `sim_session.dart`/`playtest.dart` now name exactly
`ShooterActions`, `Staged` and `stage` — the one action and the one
composition they actually touch — instead of the full barrel; `sim_renderer.dart`
takes its `EntityRegistry` as an optional parameter, the same shape
`flutter3d_render_mcp`'s own `open` already uses. `SimRenderer.frame()`
supplies `wg-02`'s `WidgetSurfaceKind` this way now too, fixing a level with
a widget surface in it failing to render — not a regression from this
change, a gap this change's own new parameter closed. No tool's own
signature changed; `open`/`step`/`snapshot`/`digest`/`writeRun`/`frame` are
untouched.

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
