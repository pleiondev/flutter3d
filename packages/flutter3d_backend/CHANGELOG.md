## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* Picks the graphics backend a build draws through, with a conditional import
  rather than a runtime branch: the two pull in worlds that do not compile for
  each other's platform.
* `openDevice` was three files in each of three games and byte-identical in two
  of them.
* Deliberately does not decide resolution or shadow budget. Those are a game's
  trade against its own scene, and a shared constant would be wrong for two of
  the three.
