## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* No changes of its own. The workspace is released as a set, in the order
  `ARCHITECTURE.md` §16 gives, so this package's version moves with the rest
  and its constraints on its siblings move with it.

## 0.2.0

* Collision shapes, a broadphase grid, ray and overlap queries, and a capsule
  character controller that walks slopes, steps and ramps.
* Rigid bodies with mass, gravity, impulses, pushing and rest — no rotation
  yet, and the character controller stays kinematic on purpose.
* No Flutter and no renderer in it, which is the boundary the package exists to
  keep: it runs under `dart test`.
