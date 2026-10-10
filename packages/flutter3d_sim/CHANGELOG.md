## 1.0.0-rc.1

- **Breaking: a save from a newer codec is refused.** `EcsWorld.restore`
  throws a `SnapshotFormatException` naming a component or resource written
  at a version past the one this build registers, before it changes
  anything. It used to skip it, so a 1.1 save opened in 1.0 came up without
  those entities' state and the next save lost it for good. A codec'd
  resource the save does not hold is removed on restore: the origin stayed
  far after a rewind to before a shift.
- **A rewind keeps what changed when.** The loop's capture of its world
  (`WorldSnapshotPart`, part version 2) holds each component's change step
  (`EcsWorld.save(withChanges: true)`), so `query().changed<T>(since:)`
  answers on a resimulated step what it answered on the live one. Its digest
  leaves them out, so every recorded checkpoint still verifies. A build that
  reads part version 1 refuses a version-2 capture.
- **`.f3drun` version 5**, written by a run whose start carries those stamps
  or that has `externalInputs`. It also reserves `probes` and
  `externalInputs`, lists of objects stamped with a step, for the probes
  and external frames a later build writes. An external input may carry
  `sourceTime`, `receivedTime`, `quality` (`good`, `uncertain`, `bad`,
  `stale`, an open set), `tag` and `unit`. A top-level `parent`
  (`{digest, step}`) names the run a branch starts from. All of them are
  checked for shape and written back as read, and so is any top-level key
  this build does not know. A v4 run reads as before; the fixture is
  `test/fixtures/v5/run.f3drun`.
- **A share bundle hashes its level as a run does**: `Level.digestHex` of
  the level read, not the digest of the document as it came, so a run of a
  version-1 level can be shared. A bundle whose level this build cannot read
  is refused with the reason. A bundle or run that names the level by the
  document's own digest, as one written before 1.0.0-rc.1 does, still reads.
- **A level's digest is its content.** `Level.digestHex` no longer holds the
  format's version, so every stored `levelHash` moves once, and a format
  bump never moves it again.
- **`EngineLoop.restore` and `rewindTo` move the origin back properly**:
  every `onOriginShift` hook runs, and `OriginShifted` goes to the view on
  the frame channel. A rewind across a shift used to leave the particles,
  the audio and the scene in the frame it came from. The double-step check
  runs the hooks between its two runs too, so they no longer move twice.
- **A yawed prefab instance expands to the same bits everywhere.** It turns
  through `Portable.sinCos` rather than `Matrix3.rotationY`, which asked
  libm.
- **A genre with no run holds nothing** (`Snapshots.holdsNothing`), so the
  determinism check refuses an empty world beside a level-less genre
  instead of passing it trivially.
- **The events every genre shares are the engine's.** `actor.hurt`,
  `actor.died` and `sequence.signal` are declared by `app`, not by whichever
  genre installed first, and disabling that genre no longer takes them away
  from the others.
- **`LocalSimulation` drops what is submitted while a tape plays.** It used
  to fire on the first live step after the tape, and land on the recording
  as if it had been pressed then.
- **`EngineLoop.published` builds its first state** when something
  registered a listener before any step. A `LocalSimulation` does exactly
  that, so an `IsolateSimulation` published `PublishedState.empty` as its
  step 0.
- **`FrameCadence`**: a `cap` of nought, less or not finite is no cap, and so
  is a `refreshRate` of nought or less (it reads as not known). `cap` is a
  guarded getter and setter now, where it was a field. A display that drops
  from 120 to 60 Hz is measured in half a second, not eleven, and a late
  frame no longer pulls the rate down.
- **`PoseRecord.track` turns through the rotation matrix.** vector_math 2.4's
  `Quaternion.rotated` turns the other way, and a ghost yawed by `a` came
  back facing `-a`.
- **A level swap in a run is checked against the document as written.** The
  level's own version bump (3 → 4) had moved the digest of every swap
  recorded before it.

- **Breaking: this package re-exports nothing of another's.** The physics (all
  of 0.8's `flutter3d_physics`: `CollisionWorld`, `CharacterController`,
  `Collider`, `RigidBody`, the queries, the cloth and the fluids), the plugin
  API's loop and bus types (`LoopPhase`, `BusEvent`, `Flutter3dPlugin`,
  `SnapshotPart` and the rest), `Entity`, `SimulationVersion`, `Portable` and
  the vector crossings came through
  `package:flutter3d_sim/flutter3d_sim.dart`; a file that names them imports
  `flutter3d_physics`, `flutter3d_plugin_api` or `flutter3d_foundation`, and
  its package depends on it. `dart fix` adds the import and `dart run
  flutter3d_build:migrate` the dependency. A first game that wants one import
  takes `flutter3d_game`, which names `EngineLoop`, `InputState`, `Level` and
  `CollisionWorld` among its few.

- **`OpenKind`**, a kind that accepts a type and gives it no meaning: what
  an editor that knows no game, or a game walking a level it has no actors
  for, makes of every type a level names. It was declared twice, in
  `flutter3d_editor_core` and `flutter3d_game`.
- **The handle a view holds of a simulation is declared here**, beside the
  loop that implements it: `SimulationHandle`, `SimulationAnswer`,
  `SimulationQueryRegistry` and `SimulationCapabilityException` came from
  `flutter3d_plugin_api`, and `EntityKindRegistry` with them, the slot
  `EntityKinds` fills. The plugin API's other registry slots are no longer
  re-exported here: `DecoderRegistry` is `flutter3d_core`'s,
  `EditorRegistry` `flutter3d_editor_core`'s, `McpToolRegistry`
  `flutter3d_mcp`'s.
- **`standardStepRate` is the loop's**, defined beside `WorldTiming`; a
  world's properties no longer carry a step rate. `Portable` and the
  `vector_math` crossings are re-exported from `flutter3d_foundation`.
- **The loop finds a phase by its former name.** `LoopPhase.elements` is
  `LoopPhase.fields`; a system, a phase constraint or a data plugin that
  says `elements` lands in `fields`.

- **Breaking: a level's world is a block, and the format is version 4.**
  `Level.world` names what the level changes of the game's world —
  `gravity` (a vector, or m/s² down), `airTemperature`, `airPressure`,
  `airDensity`, `wind`, `medium` — and `Level.worldOver(game)`
  lays it over the game's, refusing an unknown medium with an
  `UnknownMaterialException`. A version-3 file's `"gravity": N` is read as
  `"world": {"gravity": N}`; `Level(gravity:)` and `Level.gravity` are
  deprecated. `Level.formatVersion` is 4, with its fixture.
- **`JumpReach.of(tuning, world:)`**: a navigation's jump arcs are baked at
  the world's gravity, so a level on the Moon plans the jumps it allows.
- **`EngineLoop(materials:)` and `EngineLoop.materials`**: the engine's
  `MaterialCatalog`, built-ins by default, reachable by a plugin as
  `host.registry<MaterialCatalog>()`.
- **Breaking: `LevelMaterial.baseColor` is a `LinearColor`.** A level file
  still stores the sRGB numbers it always did, read and written through
  `storedBaseColor`, so files and lightmap hashes do not change; a material
  made in code is `baseColor: LinearColor.fromSrgb(r, g, b)` of the old
  numbers. The package re-exports `LinearColor`.
- **Every genre's `headless` has one shape.** `GenrePlugin.headless` is a
  nullable constructor input on the base (`super.headless`), so code
  holding any genre asks the same question of all of them, and
  `headlessGamesOf(genres)` collects the blind games a telemetry or replay
  server steps, leaving out a genre the host gave none.
- **`IsolateSimulation`: the simulation in an isolate of its own.** An
  app hands `IsolateSimulation.open` a top-level factory that builds a
  `SimulationSetup` (the loop, how input reaches it, how much history it
  keeps) in the spawned isolate; the view gets the same `SimulationHandle`
  as `LocalSimulation`. Published states cross as `PublishedState.toWire`
  with their events already encoded, `submit`, `ask` and `rewindTo` cross as
  messages, and `query`, which takes a closure, is refused with a
  `SimulationCapabilityException`. The isolate steps on its own clock, or
  by `advance` with `ownsClock: false`. In a browser `open` refuses with a
  `SimulationCapabilityException`; `IsolateSimulation.isSupported` says
  which, and `SimulationSetup.local()` builds the same simulation here.
- **`RunLoop` puts a headless run on the loop's one path for state.** A
  `HeadlessRun` steps in the loop's `rules` phase and its save is a part of
  the loop's snapshots, so a tool rewinds and bisects it with
  `EngineLoop.capture`, `restore` and `rewindTo`.
- **`ReplaySide.loop` plays a tape through an `EngineLoop`**, rewinding by
  the loop's captures and playing by its tape playback; `bisectTapes` takes
  it as it takes a side made of functions. `EntityLayout.under` reads a
  layout inside a capture (`RunLoop.savePath`).
- **An actor publishes its `Gait`**: the stair its body climbed and
  whether it stands, published and never saved, so a save and its digest
  are unchanged. `PublishedActor` reads it as `steppedUp` and `isGrounded`.
- **Breaking: `ReplayRefused` is `ReplayException`** (decision H), with the
  same members.
- **Breaking: `EduDataSource` and `ActorStrides` are `abstract base
  class`es**: an adapter or strides of your own `extends` them and is
  `final` or `base`.
- **`simFormats` lists every format this package writes** — the level, the
  visibility table, the lightmap, a save, a run, the input tape, a shared
  run and a telemetry upload — for an engine's `FormatRegistry`;
  `Flutter3dView` registers it.
- **The input tape's format id is `f3d.inputTape`**, one style with the
  others; `f3d.input-tape`, what a tape was written under, still reads.
- **A snapshot field named like the envelope's keys is refused.**
  `Snapshot.toJson` throws an `ArgumentError` naming it instead of letting
  it overwrite `version` or `format`; the shape, and so every save's and
  every recorded run's digest, is unchanged.

- **A genre's run is part of the loop's snapshots, so a rollback restores
  it.** Each `GenrePlugin` adds a `SnapshotPart` under its plugin id that
  captures and restores its run through the new `captureSimulation` and
  `restoreSimulation` (every genre's own `save` and `restore`), and adds the
  run's world to the loop's `PublishedWorlds`. Before, the run lived outside
  the loop: `EngineLoop.rewindTo`, a rollback and the default
  `DeterminismCheck` covered an empty world and restored nothing.
  `loopStateOf` and `runStateOf` carry a run's own snapshot — a tape's start,
  its checkpoints — through the loop, so recorded tapes still replay.
- **A rewind always restores something.** `EngineLoop.rewindTo` throws a
  `StateError` when no state is given and none is kept, and `restore` throws
  for a snapshot that holds none of the loop's parts; `keep` keeps the state
  it starts from. The default `DeterminismCheck` refuses a loop whose
  snapshots hold nothing rather than passing it. `RewindBuffer.attach(loop)`
  keeps a buffer's keyframes as the loop's own captures.
- **Breaking: one way to register a component.** `EcsWorld.register`,
  `registerInPlace` and `exclude` are gone; `world.components.register`
  takes a `ComponentCodec` or an `InPlaceCodec`, with its version, and
  `components.exclude` says why a type is not saved. The actor components'
  codecs are `ActorCodecs`, and the body, the health and the facing are
  published, so a view reads an actor through `PublishedActor.read`. The
  migration guide shows each old call its codec.
- **Breaking: `StepSystems` orders by name, as the loop does.** `add` takes
  `label:`, `after:` and `before:` and sorts with `orderByConstraints`; the
  `order` number is gone, with `SystemRegistration.order`.
- **The boundary the view reads through is enforced.** A frame phase reads
  `LoopContext.published`, which the loop builds after every step once
  anything reads it; `LoopContext.world` throws there. The bus asserts that
  a step-channel event has a declared codec and hands the view the step's
  events encoded. `EngineLoop.queries` answers `SimulationHandle.ask`.
  `LocalSimulation.submit` queues every submission and hands them to the
  game before the recorders write the step (`EngineLoop.onStepInput`), so
  submitted input is on the tape.
- **One floating origin per world.** `EngineLoop.shiftsPhysics` moves the
  collision world with `CollisionWorld.moveOriginTo` and adds its origin to
  the snapshots, restored before the bodies written in it.
- **Every genre has the same shape.** The strategy has `StrategyPhases`,
  `StrategySimulation.systems` and `Match.publishTo`; the shooter and the
  strategy install default entity kinds; every genre's events carry a
  description.

- **Breaking: the cameras left the simulation.** `CameraRig`, `PhotoCamera`
  and `RigSettings` place a view, which no step reads, so they are
  `flutter3d_camera`'s now, beside the virtual cameras that turn the rig;
  this package no longer exports them. `dart run flutter3d_build:migrate`
  adds the dependency and the import. The lightmaps, the sequence player
  and a light's flicker look like the view's and stay: a lightmap is a
  level asset baked from the level's brushes, the sequence player steps in
  the simulation and directs its actors, and the flicker is level data the
  step reads.
- **`Level.parse` reads a level from its JSON text**, refusing text that is
  not JSON with a `LevelFormatException` like everything else a level reader
  refuses.
- **Breaking: one suffix for settings, Settings, and Descriptor in the
  HAL.** `BehaviorParams` is `BehaviorParameters`, `MovementTuning` is
  `MovementSettings`, `NavMeshConfig` is `NavMeshSettings`, `RigTuning` is
  `RigSettings`. Every settings class is `final` with a `const` constructor
  and a `copyWith` over every field; a nullable field is reset with
  `copyWith(clearX: true)`. `dart fix` carries the renames.
- **Breaking: public constants are lowerCamelCase, without the k prefix,
  as Effective Dart asks.** `kScale` is `irradianceScale`. The values are
  the same; `dart fix` carries the renames.
- **Breaking: a step's events are on the bus and only there.** `GameEvents`
  and `StepEvents` are gone, with `GenrePlugin.eventsOf` and
  `Cutscene.signals`. A simulation publishes each event onto the bus it was
  handed at the moment it happens, so nothing is buffered, capped or
  drained: `ActorSystem.events` and `SequencePlayer.events` are an
  `EventRegistry?`, and a genre hands its run the bus through
  `GenrePlugin.publishEvents`, which installs call when the run is set. A
  game subscribes with `onStep` or `onFrame`, or reads the whole step at its
  end from the new `StepEventSummary.events` through `EngineLoop.onStepEnd`.
  A simulation stepped by hand, a test's or a server's, publishes onto a
  `DirectBus`, which hands each event out as it is published. The events
  every genre shares are declared with codecs by `declareSimulationEvents`,
  which each genre calls as it installs: `ActorHurt` is `actor.hurt`,
  `ActorDied` is `actor.died` and `SequenceSignal` is `sequence.signal` (the
  signal's own name is `SequenceSignal.signal`). An event's `name` is now
  the name it is declared under, so its codec is what a run's event digest
  folds in; a run recorded before this reports its events as diverging at
  the first step with one.
- **Breaking: a boolean reads as a question, and no `bool` is positional.**
  `Automap.everythingRevealed` is `isEverythingRevealed`;
  `Blackboard.running` is `isRunning`; `Cutscene.played` is `wasPlayed`;
  `LevelDiff.presentationOnly` is `isPresentationOnly`;
  `Mover.reverseWhenBlocked` is `reversesWhenBlocked`;
  `MovingPlatform.reverseWhenBlocked` is `reversesWhenBlocked`; `Pace.behind`
  is `isBehind`; `RewindBuffer.keyframeDue` is `isKeyframeDue`;
  `SequencePlayer.finished` is `isFinished`; `TelemetryConsent.asked` is
  `wasAsked`; `TelemetryConsent.granted` is `isGranted`; `EngineLoop.paused`
  is `isPaused`; `SnapshotFields.flag` takes `{bool orElse}`. `dart fix`
  carries the renames.
- **Breaking: units in names (docs/CONTRACTS.md).** `StepTimeTrace` speaks
  seconds: `millis`, `meanMillis` and `worstMillis` are `seconds`,
  `meanSeconds` and `worstSeconds`, and `observe` takes seconds; a written
  trace keeps its milliseconds. A cutscene's `CameraKey.fov` is `fovY`, in
  radians, read from the file's degrees, and `Sequence.cameraAt` returns
  radians. `CameraRig.extraFov` is `extraFovY`.
- **Breaking: one verb per job.** A read that empties what it reads is
  `drain`: `TriggerVolume.takeOutcome` is `drainOutcome`. `Tunables.take` is
  `readFrom`, `KeyRing.take` is `add`, and `PrefabInstance.make` is `create`,
  the synchronous creation verb. `dart fix` carries them.
- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `analogueValues` is `analogValues`, `armour` is `armor`,
  `armourShare` is `armorShare`, `AvoidanceNeighbour` is
  `AvoidanceNeighbor`, `behaviour` is `behavior`, `BehaviourBrain` is
  `BehaviorBrain`, `BehaviourChildren` is `BehaviorChildren`,
  `BehaviourComposite` is `BehaviorComposite`, `BehaviourContext` is
  `BehaviorContext`, `BehaviourKinds` is `BehaviorKinds`,
  `BehaviourKindsRegistry` is `BehaviorKindsRegistry`, `BehaviourLeaf` is
  `BehaviorLeaf`, `BehaviourParams` is `BehaviorParameters`,
  `BehaviourPathStep` is `BehaviorPathStep`, `behaviours` is `behaviors`,
  `BehavioursRead` is `BehaviorsRead`, `BehaviourStatus` is
  `BehaviorStatus`, `BehaviourTree` is `BehaviorTree`, `BehaviourTreeRead`
  is `BehaviorTreeRead`, `BehaviourView` is `BehaviorView`, `centre` is
  `center`, `centreOf` is `centerOf`, `centreOfCell` is `centerOfCell`,
  `centreX` is `centerX`, `centreY` is `centerY`, `centreZ` is `centerZ`,
  `colour` is `color`, `defaultBehaviour` is `defaultBehavior`,
  `HasBehaviourTree` is `HasBehaviorTree`, `LightBehaviour` is
  `LightBehavior`, `maxNeighbours` is `maxNeighbors`, `metresPerTexture` is
  `metersPerTexture`, `neighbourAt` is `neighborAt`, `neighbourDistance` is
  `neighborDistance`, `neighbours` is `neighbors`, `texelCentre` is
  `texelCenter`, `texelsPerMetre` is `texelsPerMeter`. Only the Dart names
  changed: a file keeps the keys it was written with, and `dart fix`
  carries the renames.
- **Breaking: the simulation is an ECS run by `EngineLoop`, and a system
  reaches it as `LoopContext.world`.** `EcsWorld` implements the plugin
  API's `SimWorld` (queries with `having`/`without`/`changed`, resources,
  deferred commands) and files every component under a versioned
  `ComponentCodec`; the old `register`/`registerInPlace`/`exclude` build one.
  The type-parameter query is `queryOf<A>()` now, since `query()` is the
  builder. A save with nothing past version 1 writes the bytes it always did.
- **Breaking: `EngineLoop` takes `world:` (the `EcsWorld`) and `timing:`
  (the `WorldTiming` that was `world:`); `changeWorld` is `changeTiming`.**
  It owns `snapshots` (`Snapshots`, the world first), with `capture`,
  `restore`, `digest`, and `rewindTo(step, state:)` restores through them —
  or through a capture it kept (`keep`). `DeterminismCheck` with no functions
  uses the same snapshots.
- **What the view reads: `published`, `onPublished`, `LocalSimulation`.**
  After every step the loop builds a `PublishedState` while anybody listens;
  `LocalSimulation` is the in-isolate `SimulationHandle`.
- **A floating origin.** `EngineLoop.shiftOrigin` moves it, calls the hooks
  (`onOriginShift`, `shiftsPhysics` for a `CollisionWorld`) and publishes
  `OriginShifted`; the origin is in the world's snapshot while it is away
  from zero.
- **Breaking: `GameLoop` and `FixedStep` are gone, and so is the deprecated
  `ActorSystem.focusBody` setter.** `EngineLoop` is the one loop; `step`'s
  `focusBody:` and `foci:` name the body.
- **Breaking: `RunOutcome` and `MoverState` are classes with constants**, so
  a later minor can add one; a `switch` over them needs a default, and
  `RunOutcome.byName` reads a word back.
- **Breaking: `HeadlessGame`, `HeadlessRun`, `RestorableRun`, `OrderedGame`
  and `TelemetrySink` are `abstract base class`es with defaults.** A game
  `extends` them. `HeadlessRun.position` and `eye` are `WorldPosition`s
  (`eye` a getter, defaulting to `position`); `reading` has a default.
  `VersionedSimulation` is gone: `HeadlessGame.simulation` answers, null by
  default. `resimulate` takes the `physics` it replays on.
- **Breaking: a level names everything in it by an id (level format 3).**
  Every brush, light and entity carries an `id`, an entity's properties sit
  under `props` and a plugin's under `components.<namespace>`, and a prefab
  instance's overrides are keyed by id paths (`k3f9a2b1/oz6whrfj`) rather
  than by name or `#<index>`, so renaming or reordering an entity inside a
  prefab no longer silently retargets the overrides written against it. The
  top level of an entity row is the format's (`EntityDef.reservedKeys`), so
  a key added in a later minor cannot collide with a game's property. A
  level from before reads as it always did: ids are derived from what each
  row is (`LevelIds.derive`), the same on every load and platform, because a
  level's digest is what a recorded run is checked against; properties at
  the top of a row are taken as properties; and name paths are turned into
  id paths (`legacyOverridesToIds`). It is written back at version 3, with
  the format envelope (`Level.format`, `f3d.level`), keeping every key it
  does not know; the envelope is not part of `digestHex`. Things the editor
  adds get `LevelIds.fresh()`. `prefabSegment` takes the entity alone and
  answers its id, and `Level.fromJson` takes `understands:`, the plugin
  namespaces whose components a reader keeps.
- **A level written again as version 3 is not an edit.** `diffLevel`
  compares rows without their `id`, and a prefab instance's overrides by
  the place each id path reaches in its template, so a version 2 level
  whose ids were handed out fresh by a tool, rather than derived on load,
  patches in as nothing instead of replaying the run.
- **Breaking: what a level writes for a light type or a shadow mode is a
  table, not a Dart name.** `LevelLightType.wireName`/`fromWireName` and
  `ShadowCasting.wireName`/`fromWireName` hold the words, so a rename of the
  enum value cannot change a saved level or a lightmap's level hash. The
  words are the ones files already have.
- **Breaking: the level's readers throw the level's exceptions.** A
  heightfield section that is not one throws `LevelFormatException`, where
  it threw `dart:core`'s `FormatException` (and a malformed `origin` or a
  `heightfield` that is not an object, which used to read as absent, is now
  refused); a lightmap sidecar throws the new `LightmapFormatException`. The
  visibility table (`LevelVisibility.format`, `f3d.visibility`) and the
  lightmap (`Lightmap.format`, `f3d.lightmap`) declare their formats, and
  the table writes the envelope and keeps the keys it does not know.
- **Every file a run is made of says what it is.** A `.f3drun`
  (`Demo.format`, `f3d.run`), a save (`Snapshot.format`, `f3d.save`), a share
  bundle (`f3d.share`), a telemetry upload (`f3d.telemetry`) and an input tape
  (`f3d.input-tape`) start with the format envelope from
  `flutter3d_plugin_api` — `format`, `version`, `requires`, `generator` — and
  are read through their `FormatSpec`, which refuses another format's
  document, a newer version and a `requires` this build does not know, each
  with the sentence. The envelope is additive, so no version moved and a
  build from before still opens what this one writes. An input tape now
  always writes its version, 1 included.
- **Unknown top-level keys survive a read and a write** in a run, a share
  bundle, a telemetry upload and an input tape: `Demo.unknown`, and
  `FormatDocument.unknown` on the others, are written back as they came.
- **Breaking:** `ShareBundle`, `TelemetryUpload` and `InputTape` extend
  `FormatDocument`, and each constructor takes `unknown`. The pieces of a run
  throw their own `Flutter3dFormatException` instead of `dart:core`'s
  `FormatException`: `EventTraceFormatException`, `PoseRecordFormatException`,
  `SimulationVersionFormatException`, `LoopChangeFormatException` and
  `InputTapeFormatException`. Catch them by name, or catch
  `Flutter3dFormatException`.
- **The barrel shows the format types** — `FormatSpec`, `FormatDocument`,
  `FormatMigration`, `FormatRefusal`, `DocumentFormatException`, `FormatRegistry` — and
  `Flutter3dFormatException`, so a game catches and reads formats without a
  second import.
- **Breaking:** `DataSourceTraceFormatException`, `DemoFormatException`,
  `DigestTraceFormatException`, `LevelFormatException`,
  `SnapshotFormatException`, `StepTimeTraceFormatException` and
  `VisibilityFormatException` extend `Flutter3dFormatException` instead of
  implementing `Exception` directly, and so do `HeatmapFormatException`,
  `ReplayException`, `ShareFormatException` and
  `TelemetryUploadFormatException`, which are new in this release. The names
  and members are unchanged and every `on` clause that caught them still does;
  every exception the engine throws now hangs from `Flutter3dException` in
  `flutter3d_plugin_api`, in one of four families: format, capability, plugin
  and resource. The migration table marks them as nothing to do.
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

- **Actions have kinds, and a game declares them.** `InputAction` is the
  sealed family: `GameAction` is its button, `AxisAction` one number in
  `[-1, 1]` and `DualAxisAction` two, with `move` and `look` the two every
  game has (`moveAxis` and `lookDelta` answer for them). `InputState` gains
  `axis`, `dualAxis`, `valueOf`, `setAxis`, `setDualAxis` and their clears.
  `ActionSet` is what a game or a genre declares, with labels for a
  rebinding screen; `ActionKind` names the kind.

- **Tapes record action values, and old tapes still play.** An `InputTape`
  now has a `version`: 2 adds each step's axis and dual-axis values, and is
  written only when a run has any, so a `.f3drun` is written at 4 only then.
  A version-1 tape of a game whose axis used to be two buttons is upgraded by
  `ActionSet.upgradeTape` from the pair its declaration names, and
  `InputTapePlayback` takes the set to do it. Playback puts the move action at
  exactly the recorded value (`InputState.replayMoveAxis`) instead of summing
  the stick and the held directions again.

- **Breaking: `InputTapePlayback`** takes an optional `actions`. A call is
  unchanged; see the migration table.

- **A frame-rate cap on an even cadence** (`A1.5`). `FrameCadence` draws
  on every n-th refresh, n the refresh rate over the cap rounded up — sixty
  on a 120 Hz screen is every other refresh, fifty is every third — and
  counts refreshes from the vsync timestamps, so a missed one counts
  towards the next frame. `EngineLoop.cadence` and `frameAtVsync` run a
  frame only on the refreshes it draws on, handing that frame every second
  since the last one.

- **A level carries the render settings it asks for.** `Level.renderSettings`
  is the `renderSettings` section, settings by slot id as JSON, which
  `SettingsExtensions.fromJson` in `flutter3d_core` decodes against the
  slots a renderer's plugins added. It is kept as written, so an id no
  installed addon knows survives a save. Additive: a level without the
  section reads, writes and digests as before.

- **Prefabs, with overrides that nest.** A level's `prefabs` are templates
  of entities by id; an entity of type `prefab` is an instance of one, at
  its own place and facing, with `overrides` addressed by path
  (`top/bulb`) and key (`glow.strength`). A prefab may hold instances of
  other prefabs, and the override written nearest the level wins.
  `expandRecipes` expands instances too, so the loader, the validator and
  the bakes see the entities, and a change to a template reaches every
  instance. A prefab that contains itself is refused with its chain
  (`prefabCycle`); an override that names nothing is a validator warning
  (`prefabIssues`). `PrefabInstance`, `expandPrefabs`,
  `expandPrefabInstance`, `applyPrefabOverride`, `mergePrefabOverrides`
  and `prefabSegment` are the pieces an editor builds on.

- **Depth layers in the level document.** `Brush.depthLayer` and
  `LevelMaterial.depthLayer` say which layer a surface is drawn on, so road
  paint and the road never trade pixels. A brush without one takes its
  material's; `BrushSurface.depthLayer` carries the answer to the renderer,
  and brushes on different layers are never batched together.

- **Breaking: `Level.formatVersion` is 2.** Version 2 is prefabs and depth
  layers. Every version-1 level reads as before, and a level that uses
  neither is still written as version 1, so it opens in older builds too.
  Code that compared a document's version with `Level.formatVersion` to
  decide whether it reads should read every version up to it.

- **Games played by orders can be played blind.** `OrderedGame` sits beside
  `HeadlessGame` and lists a game's orders as `GameOrder`s. `OrderTunes`
  writes an order into the input as one-step tunables, so it goes on the
  tape with its step and replays with it.

- **A debug build can step twice to prove a step.** Hand `EngineLoop` a
  `DeterminismCheck` — how to capture, restore and digest the world — and,
  with assertions on, each checked step runs from a snapshot, the snapshot
  goes back, and the step runs again. The first system whose digests
  differ between the two runs is named, with the plugin that added it, in a
  `StepDivergence`: everything before it agreed, so it read something a step
  may not. A snapshot that leaves state out is reported as the snapshot's
  fault, and a subscriber that publishes or writes differently as a
  subscriber's. The second run is the real one: recorders, tapes and the
  frame channel see the step once. A release build never steps twice.

- **A behaviour tree's composites are open.** The six the reader owns
  (`sequence`, `selector`, `utility`, `invert`, `alwaysSucceed`,
  `cooldown`) run as before. A game adds its own with
  `BehaviorKinds.composite`: a `BehaviorComposite` that ticks its
  `BehaviorChildren` in whatever order it decides and keeps what it
  remembers in the actor's board, so it is in every snapshot. A document
  names it as it names the built-in ones, over `children` or one `child`. A
  composite cannot take a built-in composite's name or a leaf's, and a leaf
  cannot take a composite's. `BehaviorKindsRegistry` is the same table as
  the plugin host hands it out: a plugin's leaves, considerations and
  composites go when the plugin is switched off, and a standard kind it
  replaced comes back.

- **Levels, saves and the rest read every older version.** The level, the
  save's `Snapshot`, the share bundle, the telemetry upload and the lightmap
  read every version up to the one this build writes. The JSON formats lift
  an older document through a migration list before reading a field. Only a
  file from the future is refused, with a sentence saying to update. The
  lightmap read only its exact version before. Each format has a version 1
  fixture under `test/fixtures/v1/` that `format_fixture_test.dart` reads.

- **A run says which simulation it was recorded on, and carries its poses.**
  `Demo.simulation` is a `SimulationVersion` — the engine's number
  (`SimulationVersion.engineVersion`, 1) and a genre's. A patch never
  changes either; a minor that changes how a body moves bumps the one that
  owns the change. `Demo.refusalOn` and `Demo.checkSimulation` refuse a
  tape from another simulation with a sentence naming both, before a step
  is played (`ReplayException`). `Demo.poses` is a `PoseRecord` written
  beside the tape by a `PoseRecorder`: each named body's place and
  rotation every few steps, to a millimetre. It plays on any build, and
  `PoseRecord.track` turns one body into the ghost's `Tape`. Both fields
  are additive, so `Demo.formatVersion` stays 3. A run without a
  simulation is read as version 1. Older formats reach the current one
  through `Demo`'s migrator chain, and `test/fixtures/v1..v3/run.f3drun`
  hold one file per version. `VersionedSimulation` is the opt-in for a
  `HeadlessGame` that can say its number. `bin/f3drun_info.dart` prints
  both.

- **Breaking: `flutter3d_physics` is re-exported by name**: the world, the
  queries, the controller, the backends a game plugs in and what the fluid and
  cloth guides name. The helpers underneath (`stokesSpeed`, `orificeFlow`,
  `standardAtmosphere`) are `flutter3d_physics`'s.

- **Breaking: `ActorDirector`, `HasBehaviorTree`, `Damageable` and `Rider`
  can no longer be implemented outside their own library: each is an `abstract
  base mixin class` now, so a game or a test mixes it in (`with`) and its
  class is `final` or `base`. A member added to one in a 1.x release arrives
  with a body, which an `implements` could not have taken without breaking
  somebody. `HeadlessGame`, `HeadlessRun`, `RestorableRun` and `TelemetrySink`
  stay implementable, and say so.

- **`EngineLoop` owns the frame.** One call a frame runs the input, the
  fixed steps phase by phase (`input`, `movers`, `physics`, `elements`,
  `rules`, `publish`), the post-step, and the frame phases (`animate`,
  `audio`, `camera`, `render`, `ui`). Games and plugins add phases and
  systems with named `after`/`before` constraints, sorted at the next step
  boundary, with ties going to registration order. A cycle is an error that
  names its systems. Every demo and the Flame bridge run on it now, and
  the variable-step demos (Hollow, Reef, Water, the sandbox) step a fixed
  `dt` at the world's rate. `resetClock` forgets the time a level spent
  loading without announcing it as lost.

- **`GameLoop` is deprecated for `EngineLoop`.** Nothing in the repository
  uses it now. What a game's `onStep` did is a system in a step phase, and
  the recorders, the playback, the pause and the look spread over the steps
  behave as they did. It is removed in 2.0.0.

- **Time belongs to the world, and lost time is announced.** The step rate
  comes from a `WorldTiming` (60 Hz unless the world says otherwise). The
  time scale changes how many steps a real second runs, never `dt`.
  `CatchUp.announce` drops what a frame cannot run and `CatchUp.within`
  carries a bounded debt to later frames. Both publish `TimeLost` on the
  frame channel instead of dropping time silently.

- **A typed event bus with a step channel and a frame channel.** Step events
  reach every subscriber in a fixed order at the step's end and are digested
  per step. The frame channel does not show a resimulated step's events
  again: it reconciles them with what it showed, and `onRetracted` hears what
  a correction took back. `GameEvent` is a `BusEvent`, and
  `GameEvents.forwardTo` puts a genre's existing events on the bus without
  changing what its drain returns.

- **Plugins switch at a step boundary, and a run file remembers.** The loop
  owns a `PluginManager` and journals every change it makes (plugins, step
  rate, time scale) as a `LoopChange` with its step. `schedule` replays a
  journal. `Demo` carries `loopChanges` and an `EventTrace` of each step's
  event digest. The format goes to version 3, which is written only when a
  change alters the simulation. Every older run still reads, and a run with
  only a time scale or a view plugin in it is still written at the version
  it was before.

- **Entity kinds come from the plugins installed.** `EntityKinds` fills
  the plugin host's `EntityKindRegistry` slot: a genre plugin adds the
  kinds its levels name in `install`, and switching it off takes them out
  at the next step boundary. Two plugins claiming one type name are
  refused with both named. `registry()` is the `EntityRegistry` a level is
  validated and spawned against, the application's kinds first. Handed to
  the loop among its registries: `EngineLoop(registries: [EntityKinds()])`.

- **A level can name its world's gravity.** `Level.gravity`, m/s², read
  from a `"gravity"` key beside the fog and written back only when it is
  there, so a level that does not name one reads, writes and digests as
  before and plays under its game's own gravity. Nought is a level without
  gravity; a negative number is refused. `diffLevel` and `LevelPatch` count
  a change of it as a change to the simulation, not to the picture.

- **Levels from a seed and some rules (N11).**
  - `collapse` is wave function collapse over tiles.
  - `generateLevel` lays out rooms joined by corridors, with the player in
    one room and the exit in the farthest, held to `ExitReachable`. Off the
    thread with `generateLevelOffThread`.
  - `erodeThermally` and `erodeHydraulically` shape a `Heightfield`.

- **Decals, mirrors and camera screens in the level format.**
  `DecalKind`, `ReflectorKind` and `CameraScreenKind` each name a level
  material, and are refused when the material is missing or a number would
  make them nothing.

- **`RestorableRun`** marks a headless run that can be put back to a
  saved state, which `bisectTapes` needs on each side. The shooter's run
  implements it.

- **A run sent as telemetry keeps its physics**, so the server replays it
  on the backend it was played on.

- **The flow field follows breaches.**
  - `NavGrid.rebake` re-bakes the columns a hole changed and measures the
    room again. It produces the same grid as a full bake, cell for cell.
  - `Navigation.grid` can be replaced, and replacing it sweeps every field
    over the new grid.

- **`resimulate` refuses a run recorded on other physics.** It returns
  `ResimulationOnOtherPhysics` instead of reporting a divergence nobody
  could explain. It also attaches the run's backend to the world it
  replays in.

- **A recording says which physics it ran on.** `Demo.physics` is
  `'native'` or `'dart'`, and a replay runs on that backend; the two
  backends are not promised to agree with each other.

- **A level's tree reaches its monsters.** `SpawnContext.level` is the
  level being spawned, set by `spawnInto`, so a kind can resolve the names
  an entity gives. `HasBehaviorTree` is any brain that runs a tree, and
  `BehaviorBrain.pathOf` and `goalOf` read whichever brain it is.

- **A cutscene can ask an actor for a gesture.** A `play` cue names a
  clip; the actor stands, and on the cue's own step the player asks for it
  through `Mind.gesture`, `ActorSystem.gesture` and `ActorStrides.gesture`,
  which does nothing by default. Asked once, on that step, so a restore
  past it asks nothing again.

- **A loop can run steps now.** `GameLoop.runSteps` steps through the
  same door as `advance` — a tape being recorded gets each step, a tape
  being played gives one — without handing out any look or touching the
  clock, which is how a cutscene is skipped: its remaining steps run in
  one frame and a replay of the run steps them all. A cutscene camera's
  field of view is vertical degrees and forty-five unless a key says, the
  engine's own lens.

- **A level has cutscenes.** A `cutscene` entity carries its sequence
  document in its `sequence` property and `CutsceneKind` reads it for the
  game's step rate, reporting a document that does not read as a
  validation error with each problem. It spawns a `Cutscene` mechanism: a
  trigger, a button or a relay that names it starts it, it plays in the
  mechanisms' step, directs the actors while it plays and lets go at its
  end, plays once unless told otherwise, and is saved by name — a run
  restored mid-cutscene is the director again and steps on to the same
  bits. Its signals are drained from `Cutscene.signals`.

- **A cutscene directs actors.** A sequence's `actors` cues tell an actor
  by name to walk to a mark over the navigation mesh, look at a point,
  stand, or go back to its brain. `ActorSystem.director` takes an
  `ActorDirector`: an actor it directs neither thinks nor acts that step
  and is steered instead, and `SequencePlayer` is one, directing until a
  release or its end. Which cue an actor is under follows from the step,
  so a cutscene restored mid-walk steps on to the same bits.

- **A cutscene is a document played in the fixed step.**
  `Sequence.read` takes a camera's keys on a path, subtitles, a fade and
  signals, in seconds, and turns every moment into the step it falls on
  for the game's rate, refusing a document with every problem and where
  it is. `SequencePlayer` has one integer of state: each step it fires the
  signals that step reaches as `SequenceSignal` events, once each and in
  order, and a restore carries on without firing any twice. The camera
  runs along curves through its keys, on each key on its step, eased if
  asked; the subtitles and the fade are read for the frame drawn between
  two steps. A skip is the rest of it stepped undrawn, which ends where
  watching it ends.

- **A level keeps its behaviour trees.** `Level.behaviours` holds them by
  name as the documents `BehaviorTree.read` takes, written only when
  there are some; an entity names the one it runs in a `behaviour`
  property. `BehaviorsRead` is the `LevelRule` a game brings with its own
  `BehaviorKinds`: every tree reads, and every entity names a tree the
  level has.

- **A breach says what it broke.** `Breaches.onHole` is told the box of
  every hole as it is blown, after the brushes are cut, and
  `Breaches.onRestore` when a restore has put the walls back and blown the
  saved holes again — so whatever was baked from the brushes can follow.

- **A navigation mesh can have a part of it baked again.**
  `NavMeshSettings.tileSize` cuts the lattice into tiles, a region never
  crosses a tile's edge, and `NavMesh.rebake` bakes again only the tiles
  a change reaches, outlines their neighbours again against them and cuts
  the polygons again from every outline. The result is the changed level
  baked whole, digest for digest, on the mesh's own `NavLattice`, which
  `bake(lattice:)` takes. On the dungeon's levels at a quarter-metre
  lattice and four-metre tiles a broken wall is baked again in 2 to 5 ms,
  against 6 to 40 for the whole. Tiled, `maxEdgeError` stays under half a
  cell: a simplified edge then never crosses a cell's centre, so a floor
  reaching one cell into a tile is not simplified away and the mesh still
  covers exactly what the grid covers. Untiled meshes, the default, bake
  as before, digests and all. Refused for meshes with jumps or islands
  dropped.

- **One navigation mesh per width of body.** `ActorSystem.navMeshes`
  replaces the single mesh: a mesh is eroded by one radius, and a body
  wider than it was baked for was routed through gaps it does not fit.
  `navMeshFor` gives each body the narrowest mesh still as wide as it is,
  and none to a body wider than all of them. `NavMesh.bakeLevelFor` bakes
  a set from a roster's radii and heights, one per erosion, each for the
  widest and tallest body that shares it.

- **Finding which polygon a point is on no longer looks at all of them.**
  `NavMesh.polygonsAt` asks only the polygons indexed under the point's
  lattice column. On the platformer's ascent, 576 polygons, it went from
  most of a route's cost to a third of a microsecond, and a route across
  the level takes about twenty.

- **Actors walk past each other.** `Avoidance` is ORCA: each neighbour
  rules out the velocities that meet it within a horizon, each body takes
  half the turning, and the velocity picked is the one nearest the wanted
  one that every neighbour allows, or the one that breaks them least.
  `ActorSystem.avoidance`, when set, puts every living actor on the ground
  through it against the living actors within reach, nearest first. The
  wish it hands the controller points along the difference between the
  velocity picked and the body's own, as long as the speed picked, which
  is how the controller lands on a velocity rather than half turning
  towards it. Nothing is kept between steps. Null, the default, changes
  nothing.

- **A navigation mesh knows how high its floors are between its
  corners.** A floor and the ramp up from it can be one polygon, and its
  corners alone made the flat before the ramp a slope. The mesh keeps the
  floors a body may stand on, column by column, and `heightAt` answers
  with the column's floor nearest what the corners say. The floors are in
  `digest`, so every mesh's digest moved. A route's costs are 32-bit, as
  the web has them.

- **An actor walks to a point over a navigation mesh.**
  `ActorSystem.navMesh`, when set, is what `steerTowards`, and so the
  `goTo` leaf, routes over: to the next corner, and at a link's take-off
  a jump, asked for only once the body is running at the landing, since
  air control adds speed only along the wish. The route is found again
  every step from where the body is and nothing of it is kept, so a run
  restored mid-walk steps on to the same bits. A body that overshoots onto
  a floor's eroded rim routes back from `NavMesh.nearestPolygon`, and one
  at the end of a route that cannot arrive stops there. Null, the
  default, walks straight as before.

- **A navigation mesh can be baked with jumps.** `NavMesh.bake(jumps:)`
  scans the bake's own floors, in whole voxels, for the gaps, ledges and
  drops of at most `maxFall` that reach jumps, and keeps the shortest
  between each pair of polygons as a `NavMeshLink`. A floor's eroded rim
  is a run-up, not a gap, so no link crosses a floor a body already walks;
  something solid at the body's height is a ledge it lands on or a wall.
  `route(jumps:)` takes the links within the body's own reach and says in
  `NavMeshRoute.jumps` which legs are flights. A mesh baked without a reach
  has the digest it had before.

- **A navigation mesh finds the way across itself.** `NavMesh.route`
  runs A* over the polygons, entering each at the midpoint of the edge it
  was reached through, then pulls a string through the shared edges, so a
  body walks from corner to corner and every leg stays on the mesh.
  `costOf` prices a metre of each area, one or more, and infinity keeps a
  route off an area. A goal nobody can reach gives a route marked
  incomplete that ends at the point nearest it, on the polygon nearest
  it. Costs are counted in whole millimetres and ties go by the mesh's own
  order, so a route is the same on every machine. `polygonAt` picks, of
  the polygons over a point, the one whose surface is nearest its height;
  `heightAt` and `closestPointOn` read the surface.

- **What steps the animations is saved with the actors.** `ActorStrides`
  is an abstract class now, with `save` and `restore` doing nothing by
  default. `ActorSystem.save` writes its state beside the system's own,
  and `restore` hands it back with the actors as they now are. A rewind or
  a replay steps on to the same strides with no line in a game's save.

- **An actor's animation can walk its body.** `ActorSystem.strides`
  takes an `ActorStrides`. Once a step, for every actor, after its brain
  has acted, dead or alive, it is asked how far the actor's own stride
  carried it. The body is swept that far in place of its brain's wish.
  The simulation knows nothing of animation; a game answers through this.
  Null, the default, changes nothing.

- **A brush can say where it draws.** `Brush.drawOrder`, `drawOrder` in the
  document and written only when it is not nought, is the engine's
  `MeshNode.drawOrder` for level geometry: a water surface after the floor
  under it, a decal brush over a wall. Brushes at different places in the
  order are never one batch, since a batch draws as one; a breach keeps the
  order of the brush it cut.

- **A `.f3drun` carries the levels edited under the run.**
  `Demo.levelSwaps` holds each one as a `DemoLevelSwap`: the step it took
  effect before and the whole document, since the edited level exists in no
  asset a replay could look up. On reading, the document is checked against
  the hash written beside it, and swaps out of step order or past the end of
  the tape are refused. A run with swaps is written as format 2, so an older
  build refuses it instead of replaying it into a divergence; a run without
  any is still written as 1. `f3drun_info` lists the swaps.
- **`DigestTrace.forgetAfter`** drops the checkpoints after a step, for a
  run that was lived again from there.
- **`LevelPatch` carries an edit as the rows that changed.**
  `LevelPatch.between` matches brushes, lights and entities by the digest
  of each row (a deleted brush is one edit, not every row after it), takes
  materials by name and every other key whole. `applyTo` refuses a level
  other than the one the patch was made against, a row that is not the one
  it names, and a result that is not the level it was meant to make; when
  it applies, it says what changed without comparing the two documents.
  `LevelPatch.staleCode` is the error a game answers a refused patch with.
- **Behaviour trees and utility choices as data.** `BehaviorTree.read`
  takes a JSON document of `sequence`, `selector`, `utility`, `invert`,
  `alwaysSucceed`, `cooldown` and leaves, and answers a tree or every
  problem with where it is. Leaves and utility considerations are registered
  by kind in `BehaviorKinds`, which comes with the ones the engine's `Mind`
  can already do (`goToFocus`, `goTo`, `wait`, `seesFocus`, `check`, `set`,
  `markFocus`, …). `BehaviorBrain` runs a tree; everything it knows is a
  `Blackboard` component, so a snapshot or a rewind brings a decision back
  half made. A board ticked by another tree starts again rather than resuming
  at node numbers that now name something else.
- **`bisectTapes` finds where two runs part.** Each side is a
  `ReplaySide` — a start, a tape and the simulation's step, restore and
  capture — that keeps the states it has been asked for and plays on from
  the nearest. The search compares digests and reads the full snapshots
  once, at the step it names; it says whether that step's input differed,
  and through an `EntityLayout` which entity and component moved.
  `bracketFromTraces` narrows the search to one checkpoint interval of two
  `DigestTrace`s.
- **`EntityTracks`** reads a run as one lane per component of each entity,
  holding only the steps a value changed and closing a lane when the
  component goes. `EntityLayout.ecs` reads an `EcsWorld.save()`,
  `EntityLayout.rows` one row per entity. `RewindBuffer.oldestStep` is the
  left end of a scrubber.
- **A save says what version of the game wrote it, and an old one is
  migrated.** `SaveSchema` is a game's list of migrations, and its version is
  their count, so the version cannot move without one. `upgrade` brings an
  older run up and refuses a newer one, saying it is newer, rather than
  misreading it. `SaveRecord` is the save document: level, snapshot, schema,
  step and a digest of the run. `SaveRecord.read` never throws.
- **`resolveSaves` decides between two copies of a save** by digest and step,
  against the digest both last agreed on: the same run is in sync, a side
  still at the base lost to the one that moved, otherwise the further run
  wins, and two different runs equally far along go to the player.
- **A run leaves the machine only with the player's yes.**
  `TelemetryConsent` keeps the answer with the wording it was given to and
  when; a grant to an older wording does not count, and a damaged settings
  file reads as not asked. `TelemetryUpload.prepare` is the only way to build
  an upload and refuses without consent; it drops `Demo.recordedBy`, and the
  consent travels with the run so a server can refuse one that has none.
  `TelemetryUploader` checks consent on every send; `HttpTelemetrySink`
  posts through a `JsonPost` the caller hands in, so this package still
  imports no network.
- **`resimulate` plays a demo again and says what it did.** It checks the
  level hash, the starting state and every checkpoint, and returns a sealed
  `Resimulation`: the level changed, the start differs, the replay diverged
  (with the step), or it retraced, with the run, its outcome and a trail of
  positions.
- **`Heatmap`** bins trails into cells, counting samples and distinct runs,
  and marks where runs were lost. Its JSON is the playtest report's, so the
  editor reads both.

- **Photo mode's camera.** `PhotoCamera` flies with the world paused: look,
  tilt, zoom, and moves along its own axes with up being the world's. It is
  held on a tether round where the player stood, inside the level's box when
  there is one, and out of the walls by sweeping each move and sliding along
  what it meets. It starts by sweeping out from the player to where the game's
  camera was, so a chase camera left behind a wall does not start the photo
  there. `shouldPause` takes `photoMode`, which pauses whatever the pointer and
  the pad say, since both are flying the camera.

- **A level bakes into a navigation mesh as well as a grid.**
  `NavMesh.bake` and `NavMesh.bakeLevel` voxelise the brushes and the
  `Heightfield`, keep the floors an agent fits on and can step between
  (`NavMeshSettings`: height, step, radius, slope), erode them by the radius,
  cut them into regions, outline those, and cut the outlines into convex
  polygons with their neighbours and an area each. Unlike `NavGrid` it keeps
  a walkway and the floor under it, and walks up a ramp rather than reading
  it as a riser. Integers from the voxeliser on, so `NavMesh.digest` is the
  same on every platform; the VM and Chrome agree on six scenes, and the
  test holds them. The mesh is eroded by `NavGrid`'s own clearance rule and
  covers exactly the cells a flow field for the same body accepts. It is
  the first part of N2; the path search over it comes next.

- **A level can be shared behind a short code.** `ShareBundle` is a level
  document, its hash and optionally a `.f3drun` through it, refused when the
  run was recorded in another version of the level. `RunService` speaks the
  `v1/shares` routes over a transport the game hands in, so the package
  still has no dependency for it, and answers every call with `ServiceDone`
  or `ServiceRefused` rather than throwing. `cloud/server` speaks this
  protocol.
- **A number tuned while the game runs is on the tape.** `InputState.tune`
  sets a tunable for one step, `InputFrame.tunes` records it, playback
  applies it, and `Tunables` is the step's side: named values with defaults,
  taken from the input before the step reads them, saved into a snapshot so
  a rewind comes back with the old value. A run tuned as it was played
  replays like any other.
- **`firstDifferingPath` moved here from `flutter3d_net`**, which still
  exports it. **`RewindBuffer.keyframesAfter`** reads the snapshots held.

- **`diffLevel` says who has to act on an edit.** It compares two versions
  of a level part by part and splits the change: lights, materials, fog and
  music can be patched into a running scene; brushes, entities, the ground,
  recipes and the next level are the simulation's, and go through a timeline
  branch. Conservative on purpose: a brush that only changed material is
  still the simulation's, since its surface falls back to its material.
- **`RewindBuffer.rebaseAt`** makes one keyframe the oldest thing held, for a
  change to the world the snapshots do not carry.

- **`GenrePlugin<S>`, the shape every genre installs through.** Entity
  `kinds` and `replaceKinds`, the step as one named system
  (`systemName`, in `stepPhase`), the `simulation` being stepped with its
  events forwarded to the bus (`eventsOf`), `declareEvents`, an optional
  `headless` game, and an `uninstall` that lets go. The four genre plugins
  extend it, so a game and a tool hold any genre alike.

- **Two genres can speak one word.** `EntityKinds.add` shares a kind
  another plugin already added when it is the same kind (`==`, so one
  `const DoorKind()` however often it is written) and keeps it until the
  last holder lets go; a different kind under the type is still refused,
  naming both. `replace` and `replaceAll` put a kind over another one for
  as long as they are held and bring it back after. `holdersOf` lists who
  holds a type.

Its `flutter3d_*` dependencies ask for `^1.0.0`.

## 0.8.1+1

**Resolves on Flutter 3.44 and Dart 3.12.0.** The constraints asked for Dart
`^3.12.2` and `vector_math` 2.4.3, which were what this repository is built with rather than
what the package needs. A workspace that supports Flutter 3.44, Flame's among
them, could not depend on it. Nothing else changed.

## 0.8.1

**Several things to chase, and one sweep to chase them by.**
`ActorSystem.step` takes `foci:`, a list of `FocusPoint`s, beside the single
`focus:` it always took. `FlowField.updateAll` and `Navigation.updateAll`
sweep from every goal at once and record which one each cell's route ends at
(`FlowField.sourceAt`, `Navigation.targetOf`), so each actor attends to the
focus nearest by walking at the cost of one sweep per class of body; without
navigation it is the nearest in a straight line. `Mind.focus`,
`focusBody` and `focusVelocity` are the attended one's, `Mind.focusIndex`
says which, and `ActorSystem.focusVelocityOf` reads any of them. A single
focus behaves exactly as before.

**Damage to a focus is counted per focus.** `ActorSystem.hurtFocus(body,
amount)` credits whichever focus owns the body that was hit and says whether
one did; `damageToFoci` has the totals by index and `damageToFocusThisStep`
remains their sum. `focusBody` is set by `step`, as it always was; setting
it by hand still compiles and is deprecated, since the next `step`
overwrites it.

**A save carries every focus.** One focus is written as `lastFocus`, as
before; several as `lastFoci`.

**An actor born during play can be built again from a save.** A snapshot
fills in a world that already exists, so an actor spawned after the level
loaded had nothing to be filled in when the save was loaded afresh.
`ActorSystem.spawn(entity:)` builds an actor under an entity a restore put
back, and `EcsWorld.vacant` says whether a slot is one: restore the
allocation, build each recorded actor under its own entity, restore again for
the numbers. Same index, same order, so a restored run thinks on the same beat
as the one that was saved.

**A rollback to before something was taken puts it back.** `Takeable.restore`
removed the trigger of a thing that had been taken and never re-added it, so a
rollback past a pickup left it drawn and untakeable for the rest of the run.

## 0.8.0

**A level can carry the recipe for a room in place of its brushes.** A
document's optional `recipes: [{kind, seed, params}]` list is read into
`Level.recipes` as `LevelRecipe`s and written back as it was, so an editor
that saves the level keeps the recipe. `expandRecipes(level)` turns them into
brushes, entities and lights, and everything that uses a level calls it: the
validator, the collision world, navigation, the lightmap bake and the
visibility bake, whose brush hash covers the expansion. `levelKits` has three
kits, each drawing its chances from `GameRandom` seeded with the recipe's
`seed`: `room` (walls with doorways cut in them, reflection probes and
optional clutter), `corridor` and `scatter`. A recipe no kit can build throws
a `LevelFormatException` naming it. A level without recipes reads, writes and
hashes as before.

**`LevelSketch` is the wall arithmetic the kits draw with.** It writes the rows
a document would, so a tool that generates level files can use the same code.
`roundDecimal` rounds on the exact binary value with ties to even, the rule
the shipped level documents were written with.

**`BrushGeometry.build(perBrush: true)` makes one surface per brush.** Each
`BrushSurface` then says which brush it is in `brush`, which is how a picture
can name the brush under a pixel. The default groups brushes by material as
before.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**A level without fog comes back without fog.** `Level.toJson` wrote
`fogColor` even when the document never named one, and wrote the default back
through float32, so a hand-written level failed a round trip on that key.

**A level light's `castsShadow`, when absent, follows its type.** A
directional light casts and a point or spot light does not. The renderer now
reads the flag on the sun, and a level that never named it, `map_a.json`
among them, keeps its sun shadow. `toJson` writes the key only when it
differs from that default.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3.

## 0.7.0

* **Breaking. A `Demo` carries what a replay is verified against.** The
  constructor requires `levelHash`, `buildStamp` and `checkpoints`, a
  `DigestTrace`, beside the level name, the start and the tape, and takes
  `platform`, `recordedBy` and `dataSources` as optional. `Demo.fromJson`
  throws `DemoFormatException` for a file without the first three, so a demo
  written by 0.6.0 does not open; `formatVersion` is still 1. With them a
  reader can tell that the level changed since the recording, and a replay can
  be compared checkpoint by checkpoint against the run it claims to repeat.
  `Demo.fileExtension` is `.f3drun`.
  `DigestTrace` gained `toJson` and `fromJson` for this, with
  `DigestTraceFormatException`, and `Level.digestHex` and `contentDigestHex`
  produce the eight hex digits a `levelHash` holds.
* **A level's ground is in its collision world.** `Level.addTo` adds the
  level's `Heightfield` as one static `CollisionHeightfield`, placed so that a
  ray fired down lands where `heightAt` says the surface is. It added the
  brushes and nothing else before, so a level whose ground was a field drew a
  hill that a body fell through. A level with no field gets what it always
  got. `Heightfield.copyOfSamples` is new and is how the shape gets its
  numbers without sharing a list with a field that may be edited.
* **Ground in tiles, at a level of detail chosen by distance.**
  `HeightfieldTiles(field, tileCells:, levels:)` cuts a `Heightfield` into
  tiles a power of two cells wide and builds any tile at any level as a
  `BrushSurface`, level `l` keeping every `2^l`-th sample. Seams are closed
  with skirts: each tile edge is copied straight down, so a tile's triangles
  never depend on its neighbours and a gap two levels open has ground behind
  it. The skirt depth is measured, the furthest any level's edge strays from
  the full-resolution line, doubled. Normals come from the full-resolution
  field at every level, so a seam does not show as a change of shade.
  `TileLevelChooser` gives level `l` out to `nearest * 2^l` metres with a band
  of 0.15 either side of each threshold, and keeps what a tile had inside the
  band. Not built: geomorphing between levels and tile streaming.
* **`HeadlessGame` and `HeadlessRun`: a game as a tool that plays it blind
  needs one.** A run answers `step`, `save`, `outcome`, `position`, `eye`,
  `aim`, a one-sentence `summary` and a `reading` as data; a game names its
  `buttons`, its `registry()` and how to `start` a level. They sit here,
  beside `RunOutcome`, because the tools live above the genres and a genre
  package depends on neither a tool nor anything that draws. Before this a
  tool imported one genre and called its types.
* **A value from outside the simulation is an input to the step that read
  it.** `EduDataSource.sample(step)` is a named stream sampled once per fixed
  step, `SamplerDataSource` is the deterministic one this package can prove
  without a socket, and `DataSourceRegistry.replace` swaps a source under the
  same name from that call on. `resolveBindings` reads an entity's `bindings`
  against the registry and answers target path to value; what a target means
  is the host's decision. `DataSourceTrace` records those values a step at a
  time the way `InputTape` records a controller, rides in `Demo.dataSources`,
  and `firstStepWhere(path, test)` finds the first step a recorded reading
  satisfies a condition.
* **`StepTimeTrace`: what each step cost, keyed by step number.** `record`
  times one call with a `Stopwatch` and `observe` takes a duration measured
  elsewhere; `every` defaults to 1. A step number survives a replay on another
  machine and a timestamp does not, which is why `DigestTrace` is keyed the
  same way.
* **`remapEntitySave` carries an `EcsWorld` save across an edited level.** It
  rewrites a `save()` document from the entity indices it was written at to
  the ones a reloaded level hands out, matching by name, and reports the names
  it could not place in `dropped`. `EcsWorld` is unchanged, since `restore`
  already reads any document shaped like its own save. `Actor.name`,
  `ActorSystem.spawn(name:)`, `ActorSystem.byName` and
  `ActorSystem.nameList()` are where the names come from.
* **An entity with no position stops gaining one on save.** `EntityDef.toJson`
  wrote `at` unconditionally, and four level documents with a non-spatial
  entity came back from a round trip with an invented `[0, 0, 0]`. It is
  written when the source had it or when the position is not zero, the way
  `yaw` and `name` beside it already were.
* Still plain Dart. The floor on `flutter3d_physics` is `^0.7.0`. The archive
  carries `skills/flutter3d-sim-fixed-step/` for a coding agent, installed
  with `dart run skills@ get`.

## 0.6.0

* **A floor, and no code.** The step, the ECS, levels, navigation, saves and
  replays are byte for byte 0.5.2's. The one line that changed is the floor on
  `flutter3d_physics`, now `^0.6.0`, and it is stated for the reason it was
  stated before: ground is split across the two packages — `Heightfield` here is
  the data, `CollisionHeightfield` there is what a body stands on — so a
  resolver free to reach further back would hand a caller the first without the
  second.
* Still plain Dart. Nothing here imports Flutter, and a server replaying a run
  needs no SDK to do it.

## 0.5.2

Ground made of samples, and a crowd that walks over it.

* **`Heightfield`: the first sloped ground this level format has.** A `Brush` is
  a box, so until now the only slope a level could describe was the ramp a wedge
  makes. A field is `columns * rows` heights, `cellSize` metres apart, with an
  `origin` where sample `(0, 0)` sits, and it answers `heightAt`, `normalAt` and
  `slopeAt` about the ground rather than building anything.
  The answers are about **the triangles that are drawn, not a bilinear sheet**.
  Four samples make a quad and a quad is two triangles, so a quad is only flat
  when its corners agree; interpolating bilinearly instead describes a surface
  nobody draws, and at the centre of a cell the two differ by a quarter of
  `h00 + h11 - h10 - h01` — a unit hovering over one half of the quad and sunk
  into the other. So the field finds the triangle the point is in. The split is
  fixed at `(0,0)–(1,1)` and written down once, because a mesh builder that
  chose the other diagonal would draw ground this class does not describe and
  the only symptom would be a body standing slightly in the air.
  `slopeAt` reports radians from flat and refuses to say what is walkable — a
  tank and a scout disagree about the same hillside — and it reaches for
  `Portable.atan2` rather than `math.acos`, because `acos` is the platform's
  libm and the rule *a step asks no machine for an answer* is what keeps a run
  verified in a browser agreeing with the run a player made.
* **A level can carry one.** `Level.heightfield` is an optional section, read
  and written by `Heightfield.fromJson` / `toJson`. The heights travel as base64
  of a `Float32List`'s bytes, the way `LevelVisibility` carries its cells:
  sixteen thousand samples spelled out as JSON digits is a megabyte nobody reads
  and every editor reformats. The four numbers a person might edit by hand stay
  plain.
* **`HeightfieldGeometry` emits a `BrushSurface`**, not a new type. Terrain is
  not a brush, but what the type holds is plain arrays, and the twenty lines in
  `flutter3d_bridge` that interleave them into a vertex layout do not care where
  the triangles came from — so ground draws with no new code downstream. Its
  normals are averaged from central differences while `Heightfield.normalAt`
  returns the triangle's own: one answers what the ground looks like, the other
  what a body is standing on, and the disagreement is the point.
* **`NavGrid.bakeHeightfield`: a second source for the same lattice.** `bake`
  measures its grid from brushes and stamps each cell with the solid under it;
  ground made of samples has no brushes and its extent is the field's own, so
  the two share the cell format and nothing else. Steepness is what makes ground
  unwalkable here — `maxSlope` defaults to 0.698 radians, a hair under forty
  degrees — with `blocked` for the ground refused for a reason that is not its
  shape.
  **The step height is derived from the slope rather than taken from a level.**
  On terrain the rise between neighbouring cells is not a ledge, it is the
  hillside the slope test just allowed, so the default is the tallest rise the
  steepest walkable cell can have: `tan(maxSlope) * cellSize * 1.001`, which is
  0.42 m at the default half-metre cell. Left at the 0.4 a level's bake uses, a
  two-metre grid over ground of one part in five puts a rise of 0.4 against a
  limit of 0.4 and lets float rounding decide: 112 of 240 uphill moves survived
  the comparison and the rest were called walls. The derived height allows all
  240, and the half-metre bake all 4032 of its own.

## 0.5.1

* **`Portable`: the transcendental functions a step is allowed to call.**
  `sin`, `cos`, `sinCos`, `tan`, `atan`, `atan2`, `asin` and `exp`, built out of
  `+`, `-`, `*`, `/`, `sqrt` and the bytes of a double — all of which the
  specification pins — so two platforms cannot disagree about them. That is not
  a theoretical worry: `parity_test.dart` swept twelve `dart:math` functions
  over twenty thousand arguments under the VM and under Chrome, and only `sqrt`
  and `pow` gave the same bits. A car built on the rest replayed differently in
  a browser at twenty-three checkpoints of forty, which is a verifying server
  that cannot verify. It is forty of forty now.
  Accuracy is held to two units in the last place against `dart:math` by
  `portable_math_test.dart`, because portable and wrong is a physics bug no
  parity test could report.
* **`solver_parity_test.dart`: the rigid-body solver replays bit for bit**,
  in a browser and on the VM. Predicted — `flutter3d_physics` calls no
  transcendental — and measured anyway, because the three ways it could still
  have diverged are the broadphase's ordering, a long chain of non-associative
  additions, and a browser's `int` being a `double` under the spatial grid.
* `Motion.easeFactor`, `Interpolated` and the actor system's facing now call it
  rather than `dart:math`. `tool/structure.dart`'s new rule *a step asks no
  machine for an answer* is what keeps them there.

## 0.5.0

**Breaking.** A step can say what happened, and four types stop being closed.

* **`GameEvent` and `GameEvents`: what a step did, drained by whoever owns
  it.** A buffer rather than a stream, because a stream delivers on a later
  microtask and two simulations here reproduce a recorded run exactly — an
  event arriving between two steps is the one state no replay can reproduce.
  `ActorSystem` writes into the simulation's buffer at the moment of a death,
  so a monster killed by this step's shot lands after the shot that killed it;
  two lists read afterwards can only say that both occurred. `ActorHurt` is
  now the event rather than a value copied into one, and `ActorDied` says who
  caused it. `StepEvents.has` and `.count` answer the two questions every
  reader asks of a drained step.
* **`Difficulty`: four axes a genre applies where it decides.** What the player
  is hurt by, what their attacks are worth, how quickly the opposition reacts,
  and how much of the genre's help is on. A value class rather than an enum, so
  a game writes its own — or builds one from a slider, which a list of four
  cannot express. `opponentReaction` is a duration, so the harder settings have
  less of it.
* **`ActivationOutcome` is open**, and `abstract base`. Nothing ever switched
  over its three cases exhaustively, so sealing bought nothing and cost a game
  the ability to say what happened at its own door.
* **`StepSystem` takes a `StepContext`.** A function type is frozen the day it
  is published; the context carries `dt` and the phase, which the old shape
  could not, and can grow a field instead of breaking every system.
* **`Difficulty`, `Powers`, `Scoring` and `RunStats`.** Four pieces every genre
  wanted and at most one of them had written. Powers came out of the shooter,
  which keeps every question it answered and delegates the counting. Scoring is
  the question a tally cannot answer — what those counts were *worth*, and
  whether they came close enough together to be worth more. RunStats counts
  events, and counts nothing until a game says what to recognise.
* **`CharacterController.groundNormal`** — it measured the floor's normal to
  decide whether the body was standing on it and threw it away, so nothing
  above could tell a flat floor from a ramp.

## 0.4.2

* **A brush can say how it casts, not only whether.** `shadowCasting` in the
  document is one of `on`, `off`, `doubleSided` or `shadowsOnly` — the engine
  has had four modes since `ShadowCastingMode` was written and the format had
  two, so the two it could not ask for were the two it most needed: both faces
  recorded, for a wall one brush thick whose lit side and dark side are a
  metre apart, and a proxy that casts without being drawn. `Brush.castsShadow`
  is now the two-state view of `Brush.shadowCasting` and goes on meaning what
  it meant, an unknown word is refused with the four in the message, and a
  document that said nothing goes on saying nothing. Surfaces are batched by
  the mode rather than by the boolean, because a batch is the smallest thing
  that can answer.
* **A breach keeps the baked light on the walls it did not touch.**
  `Breaches.origins` says which authored brush each current brush was cut out
  of, and `BrushGeometry.build(origins:)` uses it to find the planned face a
  piece's face is part of and measure its place inside it —
  `LightmapLayout.uvOfPoint` and `isOnPlane` are that arithmetic. Before it,
  redrawing a level after one hole meant no atlas at all and every wall in
  every room fell back to flat ambient at once. The faces the blast itself
  made take the neutral texel, which is the one part of a breached wall
  nothing ever baked.
* **A level can ask to be reflected.** `EntityTypes.reflectionProbe` is the
  format's word for a point a room is reflected from, and
  `ReflectionProbeKind` is the kind that validates one: `radius`,
  `intensity`, `faceSize`, `levels`, `near` and `far` are all optional and
  each is refused where the renderer would otherwise assert on it at load.
  The two planes are resolved against the probe's own defaults before either
  is judged, so a document naming only a near plane past two hundred metres is
  refused here rather than at load: the far plane it did not name is still a
  far plane. Pure data to the simulation — nothing spawns and nothing is
  revealed — and
  a word a game has to put in its own vocabulary, so a game without probes
  reads the entity as unknown rather than growing a reflection it did not
  ask for.

## 0.4.1

* **Lightmaps.** `LightmapLayout` unwraps every visible brush face onto a
  planar atlas from the level alone, so the baker and the geometry agree
  without a table; `LightmapBaker` bakes the light the walls throw on each
  other by gathering — direct light with shadows through the level's own
  collision world, then bounces along cosine-weighted rays — seeded by the
  texel, so two bakes are the same bytes. `Lightmap` stores RGBM in RGBA8
  with a hash of the brushes, lights and materials, and
  `dart run flutter3d_sim:bake_lightmap` writes `<level>.lightmap.bin`.
  `BrushGeometry.build(lightmap:)` hands every vertex its second coordinate.
* **Jump links.** `NavGrid.bake(jumps:)` finds the gaps and ledges a
  `JumpReach` clears; a `FlowField` filters them by its own body's reach with
  the body's width added, relaxes them backwards at their distance plus two
  cells so a walk of equal length wins, and `jumpAt` says when the next step
  is a jump. `Navigation.jumpAhead` and `ActorSystem` take off through the
  controller's buffered request on the take-off cell.
* `Mind.heading`, for turning to face the way the field said.

## 0.4.0

* First release. It is `flutter3d_game`'s inside, moved out whole: the fixed
  step, the entity store, the level format and its validator, saves, demos and
  the rewind buffer, world logic, actors, navigation, the camera rig and the
  maths. Nothing changed behaviour; the imports moved and the package boundary
  is new.
* **Plain Dart, and that is the reason it exists.** A server that verifies a
  submitted run has to replay it through the same simulation the player ran,
  and a Flutter SDK in that container is a blocker rather than an
  inconvenience. `flutter3d_game` keeps the eight files that reached Flutter —
  the touch and keyboard widgets, the `MediaQuery` read, the diagnostics sink —
  and re-exports this package, so no existing program changes a line.
* The boundary is a check, not a comment: `the simulation names no Flutter` in
  `tool/structure.dart` scans `lib/`, `test/` and `bin/`.
* `StateDigest` and `DigestTrace` come with it — a 32-bit digest over the bits
  of a snapshot, computed the same way in a browser as in the VM, and a
  checkpoint trace that names the first step two runs disagree at.
* `dart run flutter3d_sim:bake_visibility` moves here from `flutter3d_game`,
  where it had never needed Flutter either.
