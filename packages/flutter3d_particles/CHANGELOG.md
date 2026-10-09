## 1.0.0-rc.1

- **`effectsSection` reads a data plugin's `effects`.** Registered in the
  engine's `DataSectionRegistry`, it reads the `.f3dfx` documents a
  `.f3dplugin` names or carries and installs them into `ParticleEffects`;
  the plugin runtime no longer depends on this package to do it. The file
  format is unchanged.
- **Reads gravity and wind from `flutter3d_matter`** rather than through
  the physics: `WorldProperties` and `standardGravity` are what a world is
  made of, and a particle system needs no collision world.
- **`PlacedEvent` is declared in `flutter3d_foundation`**, which this
  package does not re-export: an event of the simulation
  (`ElementExploded` in `flutter3d_elements`) says where it happened
  without depending on the particles. Import it from the foundation. New
  in 1.0, so no 0.8 code names it.

- **Breaking: a particle system lives in a world.** `ParticleSystem.world`
  (a `WorldProperties`) gives `ParticleGravity()` its gravity and the
  particles their wind; `ParticleSystem.gravity` is a getter and setter over
  it rather than a field. `ParticleGravity.world(scale:)` falls by a multiple
  of the world's, and `ParticleDrag` slows a particle relative to the wind.
- **Breaking: a burst's place is named `at`, in scene space.**
  `ParticleSystem.burst`, `emit` and `emitTimed` call their positional
  place `at` where it was `origin` (no call names it) and say it is
  relative to `Scene.origin`. `burstInWorld`, `emitInWorld` and
  `emitTimedInWorld`, and `ParticleEffects.burstInWorld` and `emitInWorld`,
  take a `WorldPosition` and narrow it with `Scene.toScene`.
* **Breaking: `ParticleSystem.emitFor` is gone**, deprecated earlier in
  1.0. It emitted a whole frame's worth at once, so what it made depended on
  the frame rate: call `emit` with the rate and `advance(dt)`, which spends
  it across fixed sub-steps.
* **Breaking: a boolean reads as a question, and no `bool` is positional.**
  `Emission.spent` is `isSpent`; `ParticleGlow.located` is `isLocated`;
  `Particle.alive` is `isAlive`. `dart fix` carries the renames.
* **Breaking: `ConeEmitter.halfAngleDegrees` is `halfAngle`, in radians**
  (docs/CONTRACTS.md): `25.0 * math.pi / 180.0` for what was `25.0`. An
  `.f3dfx` file keeps its `halfAngleDegrees` key; the reader converts.
* **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `centre` is `center`, `colour` is `color`, `randomiseStart` is
  `randomizeStart`. Only the Dart names changed: a file keeps the keys it
  was written with, and `dart fix` carries the renames.
* **`ParticleSystem.shiftOrigin`**: the particles' hook for a moving origin,
  every live particle moved the other way.
* **Breaking: `.f3dfx` is version 2, in the format envelope.** A document
  starts `{"format": "f3d.effect", "version": 2, ...}` (`EffectDocument.format`)
  instead of `{"f3dfx": 1}`. No effect key changed; a build from before looks
  for its version under `f3dfx` and refuses a version-2 file rather than
  misreading it. Version 1 documents still read, `f3dfx` and all, and are
  written back as version 2.
* **Breaking:** `EffectDocument` extends `FormatDocument`; its unknown keys
  are `unknown` (`extra` still answers the same map), and its constructor is
  no longer `const`. Every reader in the effect format throws
  `EffectFormatException` where it threw `dart:core`'s `FormatException`.
* **`EffectFormatException` is a `Flutter3dFormatException`**, under
  `Flutter3dException` from `flutter3d_plugin_api` with every other exception
  the engine throws.
* **1.0.0 is a promise: strict semver from there.** This release candidate
  already keeps it. A patch fixes bugs and
  breaks nothing, a minor adds, and a break waits for a major. The whole
  public API is stable, with no experimental exceptions, and is held to the
  snapshot in `api/`. A deprecated name stays until the next major and for
  at least six months, and says what replaces it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#the-api-is-a-snapshot)
  has the rules, and
  [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)
  says which releases get fixes and on which platforms.

* **Breaking: sparks fall by their world's gravity.** `ParticleGravity()`
  with no acceleration pulled particles down at a 9.8 of its own; it now
  reads `ParticleSystem.gravity`, the world's, which a game sets from its
  world (`NativeWorld.gravityMagnitude`, a level's gravity) and which is
  `standardGravity` for a system nobody gave one. Each step hands it to the
  live particles as `Particle.gravity`. `ParticleGravity.acceleration` is a
  `double?` now, null for the world's; an effect that names an acceleration
  keeps it, as a look. The dungeon's splinters and splashes and the racing
  circuit's tyre drops and bow spray, which wrote the 9.8 out, fall by their
  worlds' 9.81 now, **which moves their frames: the dungeon's and the
  racing demo's goldens with those particles in them are re-recorded before
  the release.**

* **Effects can be written as data.** A `.f3dfx` document (`EffectDocument`,
  `f3dfx` 1, with a fixture) describes effects in this package's own terms:
  the emitter, the count, the lifetime, size and colour, the affectors in
  order (gravity, the world's or a number of its own; drag, wind,
  turbulence, colour and size over life, gradients and curves with their
  eases, spin, and a floor to land on), how it is drawn (billboard, mesh or
  six-way sheet, its blend, texture, flipbook and softness), a standing
  rate, and the bus events it goes off on. An effect read from a document
  is the same simulation as the one written in Dart, particle for particle;
  the dungeon's blast, torch, splash, splinters and sparks are written in
  both and tested against each other. `ParticleEffects` is the registry a
  game or a `.f3dplugin` installs documents into, and an event that
  implements `PlacedEvent` places the effects it starts. Collision against
  the scene's depth is read and reported as unsupported: a simulation on
  the CPU has no depth to read, and `ParticlePlaneCollision` is the floor it
  can do.

* **The six-way smoke baker lives beside the sheet it bakes.**
  `bakeSixWay`, `smokePuff`, `SixWaySheet` and `SixWayField` moved here from
  `flutter3d_build`, so a game bakes its smoke as it starts, on any
  platform, with no build tool among its dependencies.

* **Particles through an orthographic camera fog by depth.** Every particle
  stage measured its fog from the eye's position and a mesh particle lit
  its faces by how squarely they faced it; through an orthographic lens the
  eye is only where the camera was put along its axis, so a particle off
  the axis came out foggier and a shard dimmer than the same one on it. The
  contributors now bind the view axis and the lens, and the stages measure
  from the eye's plane and against the axis.

* **Height fog, as thick as it is at the camera.** Both contributors hand
  their stages `FogSettings.densityAt` the camera's height rather than the
  density at the fog's base, so a height fog does not leave particles fogged
  as though they stood on the ground.

* **Particles follow a shader reload.** `ParticleContributor` and
  `MeshParticleContributor` drop their pipelines when the renderer relinks,
  through `flutter3d_core`'s `PassContributor.relinkShaders`.

Its `flutter3d_*` dependencies ask for `^1.0.0`.

## 0.8.1+1

**Resolves on Flutter 3.44 and Dart 3.12.0.** The constraints asked for Dart
`^3.12.2` and `vector_math` 2.4.3, which were what this repository is built with rather than
what the package needs. A workspace that supports Flutter 3.44, Flame's among
them, could not depend on it. Nothing else changed.

## 0.8.1

* **A mesh particle can take light away.** `MeshParticleContributor` takes a
  `blend`, additive by default as before, and `MeshParticleContributor.darkening`
  is the other one worth having: the background times one minus the
  particle's colour, so dark smoke and soot are particles too. Adding can
  only brighten, and a game that wanted a black puff drew it a scene node
  per shard. Multiplication is commutative, as addition is, so the pool is
  still one unsorted draw. The fragment stage is unchanged: it was already
  handing back colour times alpha, and the blend decides what that means.

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
