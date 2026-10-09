## 1.0.0-rc.1

- **Breaking: a swimmer's lift is a share of gravity.**
  `SwimSettings.buoyancy` (6 m/s²) is `SwimSettings.buoyancyRatio`, 0.25 of
  the world's gravity — the same 6 at 24 m/s², and no rising out of the
  water on the Moon. `SwimSettings(` and `SwimSettings.copyWith` take
  `buoyancyRatio`.
- **`platformerWorld`, the platformer's world at 24 m/s²**, staged under each
  level's own world: the crates, the runner, the enemies' jump arcs and the
  sparks fall by one gravity.
- **`PlatformerPlugin.headless` is the base's nullable field**, passed as
  `super.headless` and still `PlatformerHeadlessGame` by default, so every
  genre's blind game is asked for the same way.
- **The run is in the loop's snapshots, and its enemies in published
  state.** `PlatformerPlugin` captures and restores its run as a part of the
  engine's snapshots and publishes the enemies' world, so a rollback restores
  the run and a view reads the guards from `PublishedState`.
  `stagePlatformer` takes the world the enemies live in (`entities:`).

- **Breaking: one suffix for settings, Settings, and Descriptor in the
  HAL.** `FollowTuning` is `FollowSettings`, `MovementTuning` is
  `MovementSettings`, `RigTuning` is `RigSettings`, `RunnerTuning` is
  `RunnerSettings`, `SwimTuning` is `SwimSettings`. Every settings class is
  `final` with a `const` constructor and a `copyWith` over every field; a
  nullable field is reset with `copyWith(clearX: true)`. `dart fix` carries
  the renames.
- **Breaking: `PlatformerSimulation.events` is gone; the run publishes onto
  the bus.** `PlatformerSimulation.publishTo` hands the run a bus, and
  `Runner.events` is an `EventRegistry?`; `PlatformerPlugin` does both when
  its `simulation` is set. Each event is published at the moment it
  happens, in the order it always was. A game that drained the buffer
  subscribes on the loop's bus, or reads `StepEventSummary.events` at the
  step's end; a test that steps a run by hand hands it a `DirectBus`. Every
  event is declared with a codec under its `platformer.` name, which is now
  also its `name` (`Landed.name` is `platformer.landed`, whether or not it
  was pounded), so a run's event digest folds in what each event carries.

- **Breaking: a boolean reads as a question, and no `bool` is positional.**
  `Hunter.hunting` is `isHunting`; `PlatformerSimulation.movedThisStep` is
  `didMoveThisStep`. `dart fix` carries the renames.
- **Breaking: `FollowCamera.extraFov` is `extraFovY`**, the vertical angle in
  radians (docs/CONTRACTS.md).
- **Breaking: `Crumbling.takeWeight` is `bearWeight`.** `dart fix` carries
  it.
- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `colour` is `color`, `recentre` is `recenter`, `recentreAbove`
  is `recenterAbove`, `travelling` is `traveling`. Only the Dart names
  changed: a file keeps the keys it was written with, and `dart fix`
  carries the renames.
- **`PlatformerSnapshotPart`**, named for the genre: the plugin API's
  `SnapshotPart` is the engine's.
- **The platformer declares its actions.** `PlatformerActions.set` is
  walking, looking, jumping and sprinting with dash and drop-through, and
  leaves out `use`, which nothing in a platformer reads.

- **1.0.0 is a promise: strict semver from there.** This release candidate
  already keeps it. A patch fixes bugs and
  breaks nothing, a minor adds, and a break waits for a major. The whole
  public API is stable, with no experimental exceptions, and is held to the
  snapshot in `api/`. A deprecated name stays until the next major and for
  at least six months, and says what replaces it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#the-api-is-a-snapshot)
  has the rules, and
  [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)
  says which releases get fixes and on which platforms.

- **The follow camera is a preset of the virtual cameras.** `FollowCamera`
  is built on `OrbitFraming` from `flutter3d_addon_camera`, with the same
  numbers, the same arithmetic and the same `CameraRig`, so it looks the way
  it did. New: `framing`, `virtualCamera` to hand it to a `CameraDirector`,
  `aim` to give it the runner without placing it, and an optional `name`.

- **The platformer is a plugin.** `PlatformerPlugin` installs the genre
  into an `EngineLoop`: its step as one system, `platformer.step`, in the
  `physics` phase; its own events declared on the bus under `platformer.`
  names, which its run publishes onto; its own entity kinds
  (`platformerKinds`, not the format's shared ones) in the engine's
  `EntityKinds`. The run it steps is set on it per level (`simulation`), and
  switching it off takes all of that out again. Nothing is global, so two
  genres go into one loop side by side.

- **The genre stages a level itself, and plays blind.** `stagePlatformer`
  is the assembly the shipped game used to keep to itself — registry,
  dynamics on the run's backend, enemies, mechanisms, runner, simulation —
  returning a `PlatformerStaged`. `PlatformerHeadlessGame` is the genre as
  a `HeadlessGame` and a `VersionedSimulation`, for the simulation's MCP
  server; a game hangs its own state on each run through `dress`.

- **What a game steps beside the run is saved with it.**
  `PlatformerSimulation.parts` takes named `PlatformerSnapshotPart`s, written under
  `parts` in the snapshot and handed back after the bodies on restore; a
  save whose dynamics carried `bodies` and `elements` still restores both.
  `didMoveThisStep` says whether the last step moved the world, so state
  stepped beside it stands still when the run does.

- **`platformerSimulationVersion`**: the platformer's simulation number,
  written into its runs and its network hello. A minor that changes the
  platformer's rules bumps it; a patch never does.

- **Breaking: `Gatherer`, `KeyTaker` and `Launchable` can no longer be
  implemented outside their own library: each is an `abstract base mixin
  class` now, so a game or a test mixes it in (`with`) and its class is
  `final` or `base`. A member added to one in a 1.x release arrives with a
  body, which an `implements` could not have taken without breaking somebody.

- **The run's gravity is the world's, and the runner reads it.**
  `Runner(gravity:)` is the gravity of the world the runner is in — a
  level's `gravity` when it names one, `Runner.runGravity`, 24 m/s²,
  otherwise — and every set of movement numbers the runner hands its body,
  the ground's, a surface's and a crouch's, is given it, so ice on the Moon
  is the Moon's ice. The grip is μ times it. `MovementSettings.gravity` stays
  the controller's own knob, which the runner now sets rather than reads;
  a run that names no gravity keeps the very tuning it was built with and
  is the run it was.

- **The runner pushes no harder than its grip.** `RunnerSettings.grip`, the
  soles' coefficient of friction, holds the controller's ground
  acceleration to μ g (1 − `Runner.lift`): 0.68, the lowest dry boot-sole
  figure Pollard, Heberger and Dempsey measured (2015). Under the run's
  gravity that is 16.3 m/s² where the controller pushed at 70, so a walk
  is reached in 0.37 s rather than 0.09 and a sprint in 0.61 rather than
  0.14; top speeds and ice are unchanged. `Runner.lift` is the share of the
  weight water bears, written by whoever owns the water before a step and
  read once, so wading in shin-deep water now slows a runner. What a ramp's
  slide strips off the speed is measured and given back, so slopes cost
  what `slopeSpeed` says and no more. A grip of nought is the old push. The
  runner's save carries `rampLoss`.

- **The runner's one-way platforms are a rule, not a predicate.** Its body
  takes `fromAboveLayers`, with `dropThrough` while dropping, so the physics
  core moves the runner too. The runner's own wall probe still asks the
  same three answers.

- **A save carries what the dynamics need beyond the bodies.** The
  simulation's snapshot holds `RigidDynamics.saveState()` under
  `dynamics` and gives it back after the bodies are restored. For
  `Dynamics` that is nothing, so a reference run's saves and digests are
  unchanged. For the native core it is the core's own state, without which
  a rewind stepped on from a keyframe would not repeat the run.

- **Breaking: `ReadoutStyle` is `PlatformerReadoutStyle`, and `KeyKind` is
  `PlatformerKeyKind`.** The shooter and racing declare their own, so a
  file importing two genres met two of each. `dart fix` renames them.

- **Breaking: `PlatformerPlugin` is a `GenrePlugin<PlatformerSimulation>`**,
  the shape every genre has. It takes `kinds` (the genre's own,
  `platformerKinds()`, unless the game hands others) and `replaceKinds`;
  `simulation`, `install` and `uninstall` are inherited. Installed beside
  another genre, a kind both add is shared when it is the same kind.

- **Breaking: `RunState` is a class with constants, not an enum**, so a
  state added in a minor release is not a break in every exhaustive
  `switch`. `running`, `fallen`, `finished`, `lost`, `values` and `name` are
  as they were; `outcome` is a field, and `byName` reads a snapshot's word.

- **A game hangs rules inside the step.** `PlatformerSimulation.systems`
  runs a game's `StepSystems` at `StepPhase.begin`,
  `PlatformerPhases.afterRunner` and `StepPhase.end`, while the world
  moves: where a wind, a current or a replacement for the runner's
  controller goes without editing the genre's step.

- **`FollowCamera(reframe:)`** replaces the camera's framing with one of
  the game's own, given the orbit preset to wrap.

Its `flutter3d_*` dependencies ask for `^1.0.0`.

## 0.8.0+1

**Resolves on Flutter 3.44 and Dart 3.12.0.** The constraints asked for Dart
`^3.12.2` and `vector_math` 2.4.3, which were what this repository is built with rather than
what the package needs. A workspace that supports Flutter 3.44, Flame's among
them, could not depend on it. Nothing else changed.

## 0.8.0

**Moves with the stack to 0.8.0**, whose `flutter3d_hardware` changes
`PassEncoder.bindTexture` to return `bool` and makes every backend forget its
bindings at `bindPipeline`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**Released with the rest of the stack at 0.7.1.** Nothing in this package
changed. The release it resolves against builds from pub.dev again and no
longer crashes Metal on the first unlit draw.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3.

## 0.7.0

* **Breaking. `bridge.dart`, and the readouts in it.** `PurseReadout`,
  `LivesStrip` and `ReadoutStyle` are widgets, and the simulation's barrel names
  no Flutter now; import `package:flutter3d_game_platformer/bridge.dart` for
  them. The library is new in this package, and the three widgets are all it
  exports: the runner, the camera and the level are drawn by the game.
  `doc/boundary-0.7.0.md` has the same move for the shooter and racing.
* **Breaking. `flutter3d_game` is no longer a dependency.** The simulation
  imports `flutter3d_sim` by name rather than through `flutter3d_game`, which
  stopped re-exporting it. A game that reached `flutter3d_game` or a simulation
  type through this package's pubspec alone names them in its own.
  `CollisionHeightfield`, which the runner switches on, arrives through
  `flutter3d_sim`'s re-export of `flutter3d_physics`, one step where 0.6.0 had
  two, and the floor that says which version has it is `flutter3d_sim: ^0.7.0`.
* **A spawned enemy carries the name its level gave it.** `EnemyKind` passes an
  entity's `name` to the `Actor` it spawns, which is what `ActorSystem.byName`
  and `remapEntitySave` in `flutter3d_sim` 0.7.0 read.
* The runner, the coins, the hazards and the checkpoints are otherwise 0.6.0's.

## 0.6.0

* **A floor, and no code.** The runner, the coins, the hazards and the
  checkpoints are byte for byte 0.5.2's. `flutter3d_game` is required at
  `^0.6.0`, and the floor is still the only place the chain can be said: the
  runner switches on `CollisionHeightfield`, which arrives here through two
  re-exports, and nothing else can state which version underneath has it.

## 0.5.2

* **The runner stands on ground made of samples.** `CollisionHeightfield`
  joined the sealed hierarchy of collision shapes, and a sealed hierarchy is
  what made the compiler name every switch that had to think about it — the
  runner's included — rather than letting one fall through to a default and
  answer wrongly for ever. It answers with the standing half-height, the same
  as it does for a box.
* Needs `flutter3d_game` 0.5.1 or above, which is where that shape reaches this
  package from. A floor rather than a note: the type arrives through a
  re-export, so nothing else can say which version underneath has it.

## 0.5.1

* The runner's facing, its movement wish and the swinging blocks call
  `Portable` rather than `dart:math`, so a run replays identically in a browser
  and on the VM. See `flutter3d_sim` 0.5.1 for what that is and why. No API
  change; a saved run from 0.5.0 replays a hair differently in its last bits.

## 0.5.0

**Breaking.** Fifteen per-step fields become events, and the genre ships its
readouts.

* **The simulation's five channels and the runner's ten are gone.** Two of them
  were bools that could carry one of a thing: two enemies stomped in a step
  made one sound, and a level whose checkpoints differ could not say which had
  just been passed. What replaces them is `PlatformerSimulation.events`, which
  the runner writes into as well — so a landing and the block that gave way
  under it arrive one after the other rather than as two flags on two objects.
* **`Runner.poundedThisStep` survives, and says why**: the simulation reads it
  later in the same step to shatter the block underfoot. That is wiring; what a
  game should read is `Landed.pounded`.
* **The game's walk over every mechanism, once a frame, is gone.** Springs,
  crumbling platforms and breakable blocks are reported by the simulation on
  the pass it already makes.
* **`PurseReadout` and `LivesStrip`.** The purse draws what is in it rather
  than a fixed list of kinds, and a run with no life limit draws nothing at
  all.
* **`Difficulty` is read in `Runner.applyDamage`**, the one door damage reaches
  the runner through.
* **Slopes, gliding and water.** A ramp is quicker down than up — by scaling
  the speed asked for rather than adding a push, because the controller's own
  friction eats any push a walkable slope could justify. A held jump turns a
  fall into a drift, after the apex, so the two meanings of that button do not
  fight. Water is a volume rather than a surface, with its tuning on the pool
  so a stream and a tar pit are two different pools.
* **Points, power-ups and a camera that looks up the road.** Collectibles gain
  a worth separate from how many they are; a chain of them is worth more and
  breaks on a death. The follow camera leads by a third of a second of travel,
  horizontally only.

## 0.4.1

* **`Hunter`**, an enemy that comes after the player across the gaps: it
  follows the level's flow field and jumps where the field says the next
  step is a jump, on a grid baked with the enemies' `JumpReach`. `kind:
  hunter` in a level's `enemy` entity, with `sight` and `patience`; it
  needs no route.

## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* No changes of its own. The workspace is released as a set, in the order
  `ARCHITECTURE.md` §16 gives, so this package's version moves with the rest
  and its constraints on its siblings move with it.

## 0.2.0

* A second genre, and the instrument that tested the first: a runner who jumps
  twice and dashes, coins, hazards, moving platforms, gates and a summit.
* Acceptance was "no edit to the engine" and it took five, all in input, each
  of which generalised the engine rather than accommodating a game.
