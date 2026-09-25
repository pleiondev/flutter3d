## 0.8.0

* **Smoke can be lit by the lights around it.** `ParticleContributor` takes
  `sixWay`, a `SixWayMaterial`: two textures holding six pictures of one puff,
  each lit from one side (right, top and back with coverage in `positive`;
  left, bottom and front with emission in `negative`), plus an `emission`
  colour and an `ambient` term. The new `ParticleSixWay` stage mixes the six
  by where each of the scene's lights really is, so a puff is bright on the
  side facing a lamp, dark in its own shade, and glows at its thin edges with
  a light behind it. The lights are the ones the renderer would give a mesh
  of the particles' bounds: the eight slots, the light list, and the clustered
  cells in a clustered view. Null, the default, keeps the additive stages and
  every existing frame as they were. `N6`
* **What a six-way draw costs.** It blends "over" what is behind it, so the
  live particles are sorted farthest first along the camera's forward every
  frame; the pool is still one draw. `ParticleSystem.writeQuads` takes
  `farthestAlong` for that sort, and `ParticleSystem.boundsInto` gives the
  sphere the lights are asked for with. The sheet is read with the camera's
  right and up, so a particle with a `rotation` turns its picture and not its
  lighting. It needs the `ParticleSixWay` stage from `flutter3d_shaders` 0.8.0.
* **`importSixWay` repacks a sheet exported in another channel layout** into
  the two textures, described by a `SixWayLayout` of `SixWayChannel`s, and
  turns each flipbook cell upright without reordering the cells.
  `flutter3d_build` has a baker that makes a sheet from a density field, so a
  project can have smoke without an asset.
* **Particles mark the pixels they cover for the temporal resolve.** They
  write no velocity of their own, so the resolve reprojected the wall behind a
  moving ember and kept nine tenths of it, and the ember showed at a fraction
  of its brightness. `ParticleContributor.encodeReactive` now draws each live
  particle into the reactive mask through the `ReactiveSprite` stage, by the
  disc's falloff or the sprite's alpha times the particle's alpha, and the
  resolve trusts its history less there. It runs only while
  `TemporalSettings.reactive` in `flutter3d_core` is above nought, which is
  off by default, and costs one more draw of the pool when on. `R4`

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**Released with the rest of the stack at 0.7.1.** Nothing in this package
changed. The release it resolves against builds from pub.dev again and no
longer crashes Metal on the first unlit draw.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3.

## 0.7.0

* **A burst can light something.** `ParticleSystem.burst` takes an optional
  `source`, and a `LightEmitter` passed there has its glow fed by the burst's
  particles, then fades and leaves the measured set on its own. Before this a
  burst's particles were born belonging to nobody, so a muzzle flash or an
  explosion cast no light however bright its colour was, while the skill in
  this package said it did. Existing calls are unchanged.

* **`flutter3d_particles_core` is back inside, and Flutter is out.** The
  simulation had been split off so a headless caller could bake a
  `ParticleSystem`; the two contributors stayed here because they imported
  Flutter, for a `debugPrint` inside an `assert` and for `flutter3d`'s barrel.
  They import `flutter3d_core` now and report a missing shader stage through
  `dart:developer`'s `log`, so the whole package is plain Dart and
  `flutter3d_model_core` depends on it directly. The public API is the same;
  an importer of `package:flutter3d_particles_core` names
  `package:flutter3d_particles/flutter3d_particles.dart` instead.

* **The pubspec follows.** `flutter: sdk` and the dependency on `flutter3d`
  are gone, and the package depends on `flutter3d_core` `^0.7.0` and
  `flutter3d_hardware` `^0.7.0`. An application that reached `flutter3d` only
  because this package brought it has to name it itself. The tests run under
  `dart test`. The archive carries `skills/flutter3d-particles-one-draw-call/`
  for a coding agent, installed with `dart run skills@ get`.

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
