## 0.3.0

* No changes of its own. The workspace is released as a set, in the order
  `ARCHITECTURE.md` §16 gives, so this package's version moves with the rest
  and its constraints on its siblings move with it.

## 0.2.0

* The screens a game has that are not the game: settings with volumes,
  rebinding and accessibility, the gear that opens them, credits, and where a
  save and a settings document are kept on each platform.
* Screen state in a Cubit rather than spread across `setState`, which is what
  makes it reachable from a test. The simulation step deliberately does not go
  through it.
