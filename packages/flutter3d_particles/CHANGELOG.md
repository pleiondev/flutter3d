## 0.5.0

**Breaking.** An ease carries its curve.

* **`KeyEase` is a value class holding the shape it applies.** Opening the list
  alone would have been useless — `easeShape` would have had no branch for a
  game's own ease. A game writes `const KeyEase('bounce', _bounce)` and every
  curve and gradient samples it without this package having heard of it.

## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* No changes of its own. The workspace is released as a set, in the order
  `ARCHITECTURE.md` §16 gives, so this package's version moves with the rest
  and its constraints on its siblings move with it.

## 0.2.0

* A pool, emitters, modifiers and a contributor that draws every live particle
  in one instanced call, on any backend the engine has.
* A particle can be a light source and can carry a texture.
