## 1.0.0-rc.1

- **The bridge takes `meshDataOf` from `flutter3d_level_scene`** and no
  longer depends on `flutter3d_app`.

- **`StrategyPlugin.headless` is the base's nullable field**, passed as
  `super.headless` and still `StrategyHeadlessGame` by default, so every
  genre's blind game is asked for the same way.
- **A match has a suffix of its own, `.match.f3drun`**, so the registry
  tells it from a `Demo` by name as well as by its envelope.

- **The strategy has the shape every genre has.** `StrategyPhases` and
  `StrategySimulation.systems` hang a game's rule at the genre's moments;
  `Match.publishTo` publishes `UnitFired` and `MatchDecided` from inside the
  step; the match is a part of the engine's snapshots; the plugin installs
  `strategyLevelKinds` unless the application hands its own; and
  `StrategySimulation` takes the world its crowd lives in (`entities:`).

- **Breaking: `Selection` is `UnitSelection`**, so the strategy's picking
  no longer shares a name with the modeller's element selection in
  `flutter3d_mesh`. `dart fix` carries the rename.
- **Breaking: one suffix for settings, Settings, and Descriptor in the
  HAL.** `MapCameraTuning` is `MapCameraSettings`. Every settings class is
  `final` with a `const` constructor and a `copyWith` over every field; a
  nullable field is reset with `copyWith(clearX: true)`. `dart fix` carries
  the renames.
- **`UnitFired` and `MatchDecided` are declared with codecs.**
  `UnitFired.codec` writes the side and the two packed entities, and
  `MatchDecided.codec` the winner; both read back whole. A run's event
  digest folds in the codec's encoding now, so a match recorded before
  this reports its events as diverging at its first shot.
- **Breaking: `ResourceNode.take` is `harvest`.** `dart fix` carries it.
- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `centre` is `center`, `centreOf` is `centerOf`, `centreX` is
  `centerX`, `centreZ` is `centerZ`, `colour` is `color`,
  `groundMetresPerTexture` is `groundMetersPerTexture`. Only the Dart names
  changed: a file keeps the keys it was written with, and `dart fix`
  carries the renames.
- **Breaking: `StrategyHeadlessGame` extends the engine's headless base
  class** (`HeadlessGame`/`OrderedGame` are `abstract base class`es now) and
  answers `simulation` as its member; `VersionedSimulation` is gone. Its run's
  `position` and `eye` are `WorldPosition`s.
- **Breaking: the bridge names the engine's material `RenderMaterial`.**
  `MeshLook.material` and the material parameters of `StrategyVisuals`
  (`ground`, `units`, `buildings`, `unseen`, `remembered`, `buildingSides`,
  `water`) are `RenderMaterial`s, the engine's renamed `Material`. Nothing
  else changed; `dart fix` renames the type (`core-Material-RenderMaterial`).
- **A match says what it is.** `MatchDemo.format` (`f3d.match`) writes the
  format envelope, so a match and a `Demo`, both `.f3drun`, are told apart by
  their `format`; keys a later build wrote are kept (`MatchDemo.unknown`). The
  envelope is additive, so the version stays 2.
- **Strategy declares its actions, and there are none.**
  `StrategyActions.set` is empty: a strategy is played by orders on its own
  tape, so a rebinding screen over it lists nothing.

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

- **The map camera is a preset of the virtual cameras.** `MapCamera` is
  built on `OverheadFraming` from `flutter3d_addon_camera`, with the same
  numbers, the same arithmetic and the same `CameraRig`, so it looks the way
  it did. New: `framing`, `virtualCamera` to hand it to a `CameraDirector`,
  and an optional `name`.

- **The strategy has a `HeadlessGame`.** `StrategyHeadlessGame` opens a map
  with a reader now inside the package, `openStrategyLevel`, and takes side
  nought's orders (select, move, attack, train) as an `OrderedGame`. The
  selection is saved with the match, and `StrategyPlugin.headless` hands the
  game to a tool.

- **The strategy is a plugin.** `StrategyPlugin` installs a match's step
  into an `EngineLoop` as `strategy.step` in the physics phase, steps
  whichever `Match` it is handed, and adds the entity kinds the
  application gives it to the engine's `EntityKinds`. A match stepped
  through it comes out the same to the bit as `Match.step` called by hand,
  so recorded matches replay unchanged. After the step it publishes
  `UnitFired` for each shot and `MatchDecided` once, on the step the match
  ends, both declared under the plugin's id. There is no `HeadlessGame`
  yet: the sim MCP drives a game through a stick and buttons, and a
  strategy is played by orders, so it needs a verb for orders and a map
  reader in this package first.

- **`strategySimulationVersion`**: the strategy simulation's number, for its
  runs and its network hello. A minor that changes how the crowd moves or
  fights bumps it; a patch never does.

- **A version-one `MatchDemo` opens again; its tape is what is refused.**
  `MatchDemo.fromJson` reads format 1 through a migrator that tags it
  `MatchDemo.preWaterSimulation`: the strategy rules from before the map's
  water and fires were in the match, numbered 0. `refusalOn` and
  `checkSimulation` refuse to replay its tape, and say why. The file's
  level, stamp and start still read. `MatchDemo.simulation` and
  `MatchDemo.poses` are new and optional. One fixture per version is in
  `test/fixtures/v<N>/match.f3drun`.

- **The map's gravity and air are its world's.** `MapWorld` takes a
  `gravity` (the Earth's, `standardGravityVector`, when none is given), and
  everything in the valley reads it from the world rather than writing 9.81
  beside it: a ram's stone is lobbed by `lobVelocity` and the pond's sill is
  set by `weirHead`, both under `world.gravityMagnitude`, and the river is
  poured at the world's air temperature. On the Moon a stone still lands
  on its mark and the same river backs up a higher head over the weir. On
  the Earth every number is the one it was, to the bit.

- **A map's water and fires are part of the match.**
  `package:flutter3d_game_strategy/map_world.dart` holds `MapWorld`: a river
  laid down a course into a pond, halls' timber and woods that burn, stones
  a ram throws. It hangs itself on the simulation's step and its entity
  world, so any loop that steps a match steps it, and any save carries the
  core's snapshot. It was the strategy demo's and was stepped round the match
  by the screen's loop. A resumed match came back to a fresh river with no
  fires, and a demo's checkpoints said nothing of either. The map's own
  content, its course and its trees, comes in as `MapWater` and `MapTree`.

- **The step has doors for what the map does to it.**
  `StrategySimulation.pace` gives each walker a share of its speed, asked in
  the walk, so the water slows a wader inside the step. Before, the walk was
  cut back after the shove had already moved the unit. `shots` lists the
  step's shots with who fired at whom; they used to be inferred from
  cooldowns that grew. `afterStep` runs what hangs after the crowd.

- **`MatchDemo.formatVersion` is 2, and a version-1 demo is refused.** Its
  start and checkpoints were taken without the map's world in the state, and
  with waders held back outside the step. The same tape cannot replay to
  them now, and the refusal says so.

- **Breaking: `map_world.dart` left the package.** `MapWorld`, the strategy
  demo's pond, river, fires and siege stones, was one map's content held to
  the genre's semver. It lives in the repository's unpublished
  `flutter3d_demo_content` now. The package no longer depends on
  `flutter3d_physics_native`.

- **Breaking: `StrategyPlugin` is a `GenrePlugin<Match>`**, the shape every
  genre has. `match` is `simulation`, as every genre's run is named, and
  `dart fix` renames it; the plugin gains `uninstall` and `replaceKinds`.

- **`MapCamera(reframe:)`** replaces the camera's framing with one of the
  game's own, given the overhead preset to wrap.

- **`StrategyVisuals`' `buildingStandsTall` and `resource` are ordinary
  parameters**, not private ones (`this._resource`), which put a private
  name in the API and needed the newest language version to call. Callers
  pass them as before.

**Moves with the stack to 1.0.0**, whose `flutter3d_hardware` gives
`PassEncoder.draw` a window of the bound indices and every `PassEncoder`
`setAlphaToCoverage`.

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

* **The first publication.** The 0.6.0 below was a number carried inside the
  workspace and never reached pub.dev: the package sat out that release waiting
  for its own acceptance, which `ARCHITECTURE.md` §16 records, and it is one of
  the thirteen packages `doc/boundary-0.7.0.md` lists as beginning here. 0.7.0
  is the number the whole shelf goes out on, so one number names one tree and
  `^0.7.0` on any `flutter3d_*` package resolves against every other. What the
  package holds is described under 0.6.0; what follows is what changed since.
* **A recorded match carries what a replay is verified against.** `MatchDemo`
  requires `levelHash`, `buildStamp` and `checkpoints`, a `DigestTrace`, beside
  the map's path, the start and the `OrderTape`, and takes `platform` and
  `recordedBy` as optional. `MatchDemo.fromJson` throws `DemoFormatException`
  for a document without the first three, so a match written by the 0.6.0 in
  this workspace does not open; `formatVersion` is still 1. No published
  version wrote such a file. They are the three fields `Demo` in `flutter3d_sim`
  0.7.0 gained, for the same reason: a reader can tell that the map changed
  since the recording, and a replay can be compared checkpoint by checkpoint.
  `MatchDemo.fileExtension` is `.f3drun`, the extension `Demo` uses.
* **`flutter3d_game` and `flutter3d_bridge` are no longer dependencies.** The
  simulation imports `flutter3d_sim` by name, and `bridge.dart`, where
  `StrategyVisuals` is, takes what it used from `flutter3d_bridge` out of
  `flutter3d_app`. The main library still imports neither the renderer nor
  Flutter; `bridge.dart` is the one file that does.
* The floors on `flutter3d`, `flutter3d_app` and `flutter3d_sim`, and the dev
  floor on `flutter3d_cpu`, are `^0.7.0`. The units, the orders, the economy,
  the fog, `Bot` and `Match` are what 0.6.0 describes.

## 0.6.0

* **In the workspace at the set's number, and deliberately not on pub.dev.**
  Everything below is in this checkout and none of it has ever been uploaded.
  The reason is the API rather than the arithmetic: a stockpile and a delivery
  count were lists of exactly two, one per side, and a package whose types
  encode how many sides a game may have cannot be the version somebody builds
  against. The counting is fixed and the package is waiting for its own
  acceptance, not for a release.
* The floors on `flutter3d`, `flutter3d_bridge`, `flutter3d_game`,
  `flutter3d_sim` and the dev floor on `flutter3d_cpu` are `^0.6.0`, so the day
  it does go out it names the tree it was built in.

* **A fourth genre, and the first one that is not about a protagonist.** Units,
  orders and a step that walks them over a `Heightfield` by descending shared
  flow fields, shoving overlapping neighbours apart and sitting everybody back
  on the ground. The shape came out of a measurement rather than a preference:
  ten thousand agents cost 256 microseconds to descend, 717 to shove everybody
  against everybody and 19 to write their transforms, so separation is applied
  to the whole crowd rather than to what a camera can see — the saving is 717
  microseconds and the price is a run that stops replaying the same way twice.
* **An order costs half a millisecond, because the grid it walks is coarse.**
  `NavGrid` is baked at two metres instead of the half-metre a shooter bakes for
  its corridors: the same field costs 8.4 milliseconds on the fine lattice and
  0.52 on this one, while descending it barely changes (375 microseconds against
  307 for ten thousand agents). `Formation` follows from the same arithmetic —
  a squad walks to one place and takes its slots on arrival, because twenty
  separate points would be twenty cells, so twenty fields.
* **The map stops being only ground.** A `Building` is a footprint and a height
  rather than a collider, so what it is to the simulation is a patch that stops
  being walkable; placing one re-bakes the grid, which costs about a millisecond
  over an eighty-metre map and happens when a player builds rather than sixty
  times a second. It also moves whoever was standing under it: a unit in a cell
  the fields can no longer reach used to hold its orders and never walk again,
  silently, for the rest of the match.
* **A side digs, spends and grows.** `ResourceNode` is what the ground holds,
  `HarvestJob` is the loop a worker runs when nobody is pointing — ten carried,
  filled at eight a second, out and home again — `Stockpile` is a side's rather
  than the map's, and `Producer` turns 25 of a pile into a unit every four
  seconds. What a side has left and what a side has ever brought home are two
  numbers, not one, because a side that spends everything it digs would show
  nought while out-earning an opponent sitting on a pile.
* **Each side has its own map, and the rules read it too.** `FogOfWar` keeps
  explored and visible apart on a lattice of its own — four metres against the
  navigation grid's two, because a twenty-metre reveal touches about eighty
  cells at four and three hundred at two — refreshed every sixth step, a tenth
  of a second at sixty. The policy that sends workers asks it, so a seam nobody
  has walked past cannot be dug and somebody has to go and look; the drawing
  half asks the same lattice, so a view shows a side's knowledge rather than the
  simulation's.
* **A side plays itself, and the match it plays is the load test.** `Bot` drives
  a side through the handles a player has, on a cadence of thirty steps rather
  than every one, and reads no clock and rolls no die. `Match` steps the
  policies before the world, ends at 400 delivered or when the ground and
  everybody's hands are empty, and answers *drawn* when neither side got
  further — two mirrored sides running one policy should finish level, and a
  match that invented a winner there would hide the bias the mirror exists to
  find. Above all of it, `MapCamera` watches a place over `CameraRig`,
  `Selection` picks units out of a ray the application unprojects, and
  `StrategyVisuals` is the only file that draws.
* **A fight, an economy and fog have since landed on top of that**, and a match
  counts its sides rather than naming two. What is still absent is line of sight
  over a ridge — sight is a radius, because a ray per cell per source grows with
  the crowd *and* with the map — and that absence is a budget rather than an
  oversight.
* Ten files of arithmetic under `src/`, and one beside them that reaches a
  renderer.
