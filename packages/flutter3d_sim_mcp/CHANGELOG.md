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
* **`par-02` folded in from `flutter3d_render_mcp`**, per the package-merge
  plan: the same agent's same conversation was two stdio servers for one
  level played and one frame diagnosed, and is now one. Its five tools —
  `diagOpen`/`diagFrame`/`diagPixel`/`diagPasses`/`diagScanNaN` — are
  renamed from their own package's bare names, the two that collided with
  this package's `open`/`frame` and the three renamed to match rather than
  read as an afterthought. `SimSession.diagnostic` holds the merged-in
  session's own state, kept apart from this session's rather than combined
  with it. `flutter3d_render_mcp` is retired; its history is this package's
  `git log` from here on.
