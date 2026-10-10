## 1.0.0-rc.1

- **The blind run's position is read against the world's origin.**
  `RacingHeadlessGame`'s `position` and `eye` took the car's float32
  position as an offset from the world's origin, which is wrong once the
  loop has moved its own.

- **Breaking: a car's gravity is the race's world's.** `VehicleSettings.gravity`
  is gone, from `VehicleSettings(` and `VehicleSettings.copyWith` too;
  `racingWorld` (`racingGravity`, 20 m/s²) is the world a race is run in,
  and `raceIn` stages it under a level's own. A tyre's grip is its μ times
  the world's g, so a "1.05 g" tyre is 1.05 × this world's, and the air drag
  follows the world's density.
- **Docs**: `airDrag` is per metre and a car's top speed is the `maxSpeed`
  clamp; the tyres' numbers are the ones the model gives (slicks +0.19 g on
  tarmac, 0.52 of road grip on grass); rolling resistance is stated against
  the core's `F3D_WHEEL_ROLLING_DEFAULT`.
- **`RacingPlugin.headless` is the base's nullable field**, a
  `HeadlessGame?` passed as `super.headless`: a `RacingHeadlessGame` for the
  circuit the host names, or null, as every genre's is.
- **The race is in the loop's snapshots.** `RacingPlugin` captures and
  restores its run as a part of the engine's snapshots, so a rollback
  restores it; every racing event is declared with a description.

- **Breaking: one suffix for settings, Settings, and Descriptor in the
  HAL.** `AiTuning` is `AiSettings`, `ChaseTuning` is `ChaseSettings`,
  `RigTuning` is `RigSettings`, `VehicleTuning` is `VehicleSettings`. Every
  settings class is `final` with a `const` constructor and a `copyWith`
  over every field; a nullable field is reset with
  `copyWith(clearX: true)`. `dart fix` carries the renames.
- **Breaking: `RacingSimulation.events` is gone; the race publishes onto the
  bus.** `RacingSimulation.publishTo` hands the run a bus, which
  `RacingPlugin` does when its `simulation` is set, and each event is
  published at the moment it happens, in the order it always was. A game
  that drained the buffer subscribes on the loop's bus, or reads
  `StepEventSummary.events` at the step's end; a test that steps a race by
  hand hands it a `DirectBus`. Every event is declared with a codec under
  the `racing.` name it is published by, which is now also its `name`
  (`LapCompleted.name` is `racing.lapCompleted`, not `lap completed (car
  0)`), so a run's event digest folds in what each event carries.
- **Breaking: a boolean reads as a question, and no `bool` is positional.**
  `VehicleController.grounded` is `isGrounded`; `RacerProgress.finished` is
  `isFinished`. `dart fix` carries the renames.
- **Breaking: units in names (docs/CONTRACTS.md).**
  `SkyPreset.sunElevationDeg` and `sunAzimuthDeg` are `sunElevation` and
  `sunAzimuth`, in radians; a track file keeps its degrees and
  `SkyPreset.fromJson` converts. `ChaseCamera.fov` is `fovY`, and
  `ChaseSettings.baseFov` and `fovPerSpeed` are `baseFovY` and `fovYPerSpeed`.
- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `centre` is `center`, `centreAt` is `centerAt`, `colour` is
  `color`, `colourAt` is `colorAt`, `fitTyres` is `fitTires`,
  `horizonFogColour` is `horizonFogColor`, `metresPerTile` is
  `metersPerTile`, `sunColour` is `sunColor`, `tyres` is `tireSet`, `Tyres`
  is `TireSet`. Only the Dart names changed: a file keeps the keys it was
  written with, and `dart fix` carries the renames.
- **Breaking: `RacingHeadlessGame` extends the engine's headless base class**
  (`HeadlessGame`/`OrderedGame` are `abstract base class`es now) and answers
  `simulation` as its member; `VersionedSimulation` is gone. Its run's
  `position` and `eye` are `WorldPosition`s.
- **A track says what it is.** `TrackDocument.format` (`f3d.track`) reads
  the format envelope, refuses another format's document or a newer track
  with the reason, and keeps keys it does not read (`TrackDocument.unknown`).
  The envelope is additive, so the version stays 1.
- **Breaking:** `TrackDocument` extends `FormatDocument`.
- **A lap says what it is too.** `GhostTape.toJson` writes the format
  envelope (`ghostFormat`, `f3d.ghost`, version 2) where it wrote a bare
  `{"version": 1}`, and `ghostTapeFromJson` reads both: a lap from before
  the envelope is version 1, the same body. A lap from a newer build, or
  another format's document, throws `DocumentFormatException` naming both versions
  instead of being read halfway. A 0.8 build still reads a version 2 lap,
  since it never looked at the version.
- **Racing declares its actions.** `RacingActions.set` is the stick that
  drives and the handbrake beside it, as `RacingHeadlessGame` reads them.

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

- **The chase camera is a preset of the virtual cameras.** `ChaseCamera`
  is built on `ChaseFraming` from `flutter3d_addon_camera`, with the same
  numbers, the same arithmetic and the same `CameraRig`, so it looks the way
  it did. New: `framing`, `virtualCamera` to hand it to a `CameraDirector`,
  `aim` to give it the car without placing it, and an optional `name`.

- **A track reads every older version.** `TrackDocument.fromJson` lifts an
  older track through a migration list and refuses only a newer one, telling
  you to update. The ring circuit as it shipped is the version 1 fixture.

- **`racingSimulationVersion`**: the racing simulation's number, written into
  its runs and its network hello. A minor that changes how a car drives
  bumps it; a patch never does.

- **Racing is a plugin.** `RacingPlugin` installs into an `EngineLoop`: one
  system, `racing.step`, in the `physics` phase, steps whichever race its
  `simulation` holds, and the race's events are forwarded to the bus while
  it is set. The genre's twelve events are declared under `racing.` names,
  so a tool lists them and a second genre in the same engine cannot take
  one. It registers nothing global and adds no entity kinds. The step's own
  order is unchanged, so runs recorded before replay as they did.

- **`RacingHeadlessGame`: a circuit a tool plays blind.** Given the
  circuit's spline, it lines the player and any AI rivals up on the grid of
  the level it is handed, drives the player from the stick (forward the
  throttle, back the brake, across the steering) with a `handbrake` button,
  and saves, restores and reports the race. It names
  `racingSimulationVersion`, so a tool refuses a run from other rules.

- **Breaking: `GroundField` and `VehicleController` can no longer be
  implemented outside their own library: each is an `abstract base mixin
  class` now, so a game or a test mixes it in (`with`) and its class is
  `final` or `base`. A member added to one in a 1.x release arrives with a
  body, which an `implements` could not have taken without breaking somebody.

- **A save carries what the dynamics need beyond the bodies.** The
  simulation's snapshot holds `RigidDynamics.saveState()` under
  `dynamics` and gives it back after the bodies are restored. For
  `Dynamics` that is nothing, so a reference run's saves and digests are
  unchanged. For the native core it is the core's own state, without which
  a rewind stepped on from a keyframe would not repeat the run.

- **Breaking: `ReadoutStyle` is `RacingReadoutStyle`.** The platformer and
  the shooter declare their own, so a file importing two genres met two.
  `dart fix` renames it.

- **Breaking: `RacingPlugin` is a `GenrePlugin<RacingSimulation>`**, the
  shape every genre has: it takes `kinds` (none by default) and
  `replaceKinds`, and `simulation`, `install` and `uninstall` are
  inherited.

- **Breaking: `RacePhase` is a class with constants, not an enum**, so the
  losing phase a race against the clock wants can arrive in a minor
  release without breaking every exhaustive `switch`. `countdown`,
  `running`, `finished`, `values` and `name` are as they were; `outcome` is
  a field, and `byName` reads a snapshot's word.

- **A game hangs rules inside the step.** `RacingSimulation.systems` runs a
  game's `StepSystems` at `StepPhase.begin`, `RacingPhases.afterVehicles`
  and `StepPhase.end`: where a slipstream, a boost pad or a replacement for
  the cars' controller goes without editing the genre's step.

- **`ChaseCamera(reframe:)`** replaces the camera's framing with one of the
  game's own, given the chase preset to wrap.

Its `flutter3d_*` dependencies ask for `^1.0.0`.

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

* **Breaking. The readouts are in `bridge.dart`.** `LapReadout`,
  `PositionReadout` and `ReadoutStyle` are widgets, and the simulation's barrel
  names no Flutter now; import `package:flutter3d_game_racing/bridge.dart` for
  them. `buildRoadMesh`, `buildVergeMesh`, `buildBarrierMeshes` and
  `RoadMeshSettings` were there already. `doc/boundary-0.7.0.md` has the same
  move for the shooter and the platformer.
* **Breaking. `flutter3d_game` is no longer a dependency.** The simulation
  imports `flutter3d_sim` by name rather than through `flutter3d_game`, which
  stopped re-exporting it. A game that reached `flutter3d_game` or a simulation
  type through this package's pubspec alone names them in its own.
* Apart from thirteen import lines nothing under `lib/src/` changed: the
  vehicle, the tyre model, the track, the AI driver and the ghost are 0.6.0's.
  The floors on `flutter3d`, `flutter3d_physics` and `flutter3d_sim` are
  `^0.7.0`.

## 0.6.0

* **The determinism table was matched on a third and a fourth machine, and not
  one number in it moved.** Forty of forty checkpoints, on ubuntu-x64 under the
  VM and under Chrome, in CI run 34121423137. This car is the one that used to
  be the counter-example — a pair recorded on 2026-09-02 disagreed at
  twenty-three of the forty from step 75 onwards — so the confirmation is worth
  more here than anywhere: the arithmetic the tyre curve now runs on carries a
  run across a processor and an operating system as well as across an engine.
  The note is in `test/parity_test.dart` beside the table it is about.
* Nothing in `lib/` changed. The version moves with the set, and the floors on
  its siblings move with it.

## 0.5.1

* **The car replays identically in a browser and on the VM.** It did not: the
  same tape drove measurably different cars, diverging at twenty-three of forty
  checkpoints from step 75, because the tyre curve and the bicycle-model
  steering are made of transcendentals and `dart:math` gives different bits for
  every one of them in the two places. The vehicle, the tyre model, the track's
  camber, the AI driver and the grid placement call `Portable` now — see
  `flutter3d_sim` 0.5.1. Forty of forty.
* No API change. What a car does is a hair different in the last bits, which is
  a saved race from 0.5.0 replaying a hair differently and nothing a player can
  see.

## 0.5.0

**Breaking.** Ten flags become events, the mode carries what it means, and the
track reads its own version.

* **Eight flags on `RacerProgress`, two on `RaceState` and one on the
  simulation are gone.** Every event names the car it happened to, which a flag
  living on one `RacerProgress` could not: a caller found out who by knowing
  whose flag it had just read, which stops working the moment anything wants
  the field's moments in the order they happened.
* **`RaceMode` is open, and carries the three questions it was already being
  asked** with `==` in four places: does it start behind lights, does it count
  progress, does it end after so many laps. A game adds elimination or a drift
  event by answering them.
* **`TrackDocument` reads its `version`.** The generator has stamped one into
  every file since the format existed and this reader took the number and
  ignored it. A missing number still reads.
* **`LapReadout` and `PositionReadout`.** The lap counter counts from one and
  stops at the last, which every game that reached for `RacerProgress.lap` got
  wrong in both directions.
* **Sectors, a tow, assists, drift scoring, a qualifying grid and a restart.**
  Sectors are the stretches between checkpoints a circuit already carries, so a
  ghost can finally say *where* a driver lost the time. The slipstream arrives
  on `VehicleInput` rather than on `VehicleController`, which answers questions
  about the car rather than doing things to it. Traction control engages on
  spin while the car is pointing where it is going — written on slip ratio
  alone it would have cut the throttle mid-drift, in a game that scores them.
  `StartGrid.orderBy` turns a qualifying result into a grid, and `restart` puts
  the field back without rebuilding the world.

## 0.4.0

* No changes of its own beyond a doc comment following `gripLimit` to its new
  name; the version moves with the workspace, whose sibling constraints name
  a single release.

## 0.3.0

* **A parked car stays parked.** `SphereVehicle` had no resistance to rolling
  at all: the downhill part of gravity went into the velocity every step, the
  tyres answer a slip rather than a speed and saw nothing to object to, and air
  drag goes as the square of the speed. The circuit's starting grid rises about
  one in fifty, so a driver who touched nothing rolled backwards and kept
  gaining — 3.97 m/s after ten seconds. `rollingResistance` costs a coasting car
  something, and `holdSpeed`/`holdSlope` hold it still below a walking pace on
  anything gentler than about one in eight. Every scene this package was tested
  on was flat, which is why nothing caught it.
* Opponents drive the same car model the player does, and the ghost is the car
  it is racing rather than the box it used to be.

## 0.2.0

* A third genre: a car with grip it can lose, a track measured in metres,
  opponents, tyre wear, damage and the lap that counts.
