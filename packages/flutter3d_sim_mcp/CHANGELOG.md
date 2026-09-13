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
