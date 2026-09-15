## Unreleased

* **`flutter3d_particles_core` is back inside, and Flutter is out.** The
  simulation had been split off so a headless caller could bake a
  `ParticleSystem`; the two contributors stayed here because they imported
  Flutter, for a `debugPrint` inside an `assert` and for `flutter3d`'s barrel.
  They import `flutter3d_core` now and report a missing shader stage through
  `dart:developer`'s `log`, so the whole package is plain Dart and
  `flutter3d_model_core` depends on it directly. The public API is the same;
  an importer of `package:flutter3d_particles_core` names
  `package:flutter3d_particles/flutter3d_particles.dart` instead.

## 0.6.0

* **Floors, and no code.** One pool, one draw call, whatever is in it — byte for
  byte 0.5.0's. `flutter3d` and `flutter3d_hardware` are now floored at
  `^0.6.0`, which is the pair this package's single batch was compiled against.

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
