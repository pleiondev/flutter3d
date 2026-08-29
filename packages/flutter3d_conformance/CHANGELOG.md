## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* No changes of its own. The workspace is released as a set, in the order
  `ARCHITECTURE.md` §16 gives, so this package's version moves with the rest
  and its constraints on its siblings move with it.

## 0.2.0

* The behaviour `flutter3d_hardware` requires, as a suite a backend runs
  against itself: formats that must be renderable, pixels that must keep their
  row order, and every stage pair the engine actually links.
* Split into `coreChecks` and `shaderChecks`, because a suite that claimed to
  need no shaders met a new backend with five failures it could do nothing
  about.
