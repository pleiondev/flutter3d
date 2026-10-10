## 1.0.0-rc.1

- **A corpse is let go when its actor stands again.** `ActorVisuals` kept
  an actor its `corpses` had taken over for good, so after a rewind to
  before the death the actor stood frozen and a second death made no
  ragdoll. It calls `ActorCorpses.end` and animates the actor again once it
  lives, and hands the next death over as the first.

- **A replay checks its simulation whether or not one is named.**
  `replayDemoOnLoop` and `rewindBufferFromDemo` refused a run from another
  simulation only when given `simulation:`; without it a newer tape played
  and parted at a checkpoint. They check against the loop's
  `EngineLoop.simulationBase` now. A game whose runs name a genre passes
  that genre's version, as it did.

- **The one facade, and the list says so.** The level, `EngineLoop` and
  `InputState` (`flutter3d_sim`), `CollisionWorld`, `Collider` and
  `RigidDynamics` (`flutter3d_physics`) and the listener, emitters and sound
  bank (`flutter3d_audio_core`) are re-exported here by name; `flutter3d`
  named them until now. No other package of the engine re-exports another's
  API to save an import, and `tool/structure.dart` holds the list.
  **Breaking:** `OriginShifted` and `RenderAnchor` no longer come through
  `flutter3d`; they are the plugin API's.

- **Breaking: `OpenKind` is `flutter3d_sim`'s.** It was declared here and,
  identically, in `flutter3d_editor_core`; `openRegistryFor` uses the one
  beside `EntityKind` now.
- **Breaking: the widgets are `flutter3d_game_ui`'s.** `TouchControls`,
  `TouchStick`, `TouchButton`, `TouchSlots`, `TouchSlot`, `TouchToggle`,
  `TouchAction`, `SettingsOverlay`, `SettingsPanel`, `SettingsSection` and
  its sections, `ActionBindingsSection` with `RebindRequest` and
  `TuningChange`, `PrivacySection`, `askWhichRun`, `syncBeforeBegin`,
  `AutomapView`, `AutomapPainter`, `Credit`, `CreditsSection`,
  `TapToRestart`, `GameUiTheme` and `Flutter3dGameLocalizations` moved
  there, beside widgets that did the same jobs. This package keeps the
  runtime: input, the run, the settings and the controller that writes
  them, the saves, and the actors and fixtures drawn. `dart fix` moves the
  imports, and `migrate` adds the dependency.

- **`LiveLevel` applies a level's world** over the game's when it swaps one
  in (`collision:`, `gameWorld:`).
- **Docs**: `SoundOcclusion.perObstacle`'s half is −6 dB, not the ten a
  door costs.
- **`ActionBindingsSection`'s callbacks take one object.** `onRebind` is
  handed a `RebindRequest` (`RebindRequest.cancel` to stop listening) and
  `onTuning` a `TuningChange`, where they took two and three positional
  arguments; `FrameInfo` and `ListenerPose` are re-exported with
  `Flutter3dView`. `BehaviorOverlay.colorOf` answers a `LinearColor`.
- **`ActorVisuals.animate` reads published state** when it has some:
  whether an actor lives (its corpse, a clip that holds its last pose) and
  which clips it plays come from its published row, and a climbed stair is
  smoothed from the published `Gait`. `ActorAppearance.clipsFrom` is asked
  with that row, and answers `clipsFor` by default; `ActorVisuals.wrapWhen`
  is `wrapFor` from a published life.
- **Breaking: `SaveFile.read` answers the `SaveRecord`**, a class, where it
  answered a record of `level` and `run`; both are fields of it, so code
  reading `.level` and `.run` is unchanged.
- **The save-slot index, the cloud-save state and the telemetry answer are
  formats with an envelope**: `SaveSlots.indexFormat` (`f3d.saveSlots`),
  `SaveSync.stateFormat` (`f3d.cloudSaves`) and `Consents.telemetryFormat`
  (`f3d.telemetryConsent`), each with a fixture. The shapes before the
  envelope still read; keys a later build added are kept; an index from a
  newer build is never written over, and a newer consent document is no
  consent.
- **`gameFormats` lists them** with the settings file and the action map,
  for `Flutter3dView.formats`.
- **Breaking: `registerTimelineExtensions` returns a `Registration`, and
  several timelines can be on the VM service.** The extensions answer for
  the most recently registered timeline still on; cancelling hands them
  back to the one before, and cancelling the last switches them off. A
  second timeline used to throw. `frameTimes`, `tracks` and `bugReport` are
  always registered and answer an error when the current timeline lacks
  what they need.
- **Breaking: `ext.flutter3d.cvar.list` answers `{"tunables": {name:
  {"value", "default"}}}`**, where it answered with the tunables at the top
  level.
- **The timeline and level extensions declare the keys they answer with**,
  so `api/flutter3d_game.vm` lists every one.

- **Breaking: the timeline rewinds through the loop.** `RunTimeline` takes
  `loop:` (the `EngineLoop` its `RewindBuffer` is attached to,
  `rewind.attach(loop)`) in place of `input:`, `stepSim:`, `restore:` and
  `stepSeconds:`: a keyframe is the loop's own capture, restored through
  `EngineLoop.rewindTo`, and a replay runs the loop's own steps with the tape
  as its playback, marked resimulated. So a rewind, a scrub, a level swap
  and a replay under new code cover every part of the state — the world,
  the genre's run, a plugin's part — and the loop's step count with it,
  where a step and a restore of the game's own put back the genre and left
  the rest. `scrubTo`, `tracks` and `replayUnderNewCode` lose `capture:`;
  `tracks` reads a part's own data with `part:`, and a divergence's path
  starts with the part it is in. `registerTimelineExtensions` registers
  `scrubTo` and `replayUnderNewCode` always and loses `capture:` (`tracks`
  takes `trackedPart:`); `replayAfterHotSwap` loses `capture:`.
- **Breaking: a run file replays through the loop.** `replayDemo` (a step,
  a save and a restore of the game's own) is gone; `replayDemoOnLoop` takes
  `part:` — the run's part of the loop's snapshots, a genre's plugin id — in
  place of `restore:` and `save:`, restores the file's start as that part and
  digests each checkpoint from it, so every tape recorded from a run's own
  `save()` checks out as it did. `rewindBufferFromDemo` takes `loop:` and
  `part:` in place of `stepsPerSecond:`, `input:`, `restore:`, `save:` and
  `stepSim:`, and builds its buffer attached to the loop. `bugReportTape`
  takes `part:`, so a report's start is the run's own snapshot, as a `.f3drun`
  holds it.
- **`ActorVisuals` draws from published state.** Given `published:` —
  `() => loop.published` — it places each actor where the step left it,
  faces it the way the step left it and lays it down when the step says it
  died, from the rows the run's world published (`PublishedActor.read`),
  not from the live actor: the view's side of the boundary, which keeps
  drawing when the simulation runs elsewhere. The dungeon draws its
  monsters this way.
- **Breaking: `GameSettings` is a value.** It is `final` with a `const`
  constructor and a `copyWith` over every field (`clearActions` goes back
  to the game's own map). A volume is per `AudioBus` (`volumeOf(AudioBus)`,
  `withVolume`), every other setting is a typed `SettingKey<T>` under a
  namespaced id (`valueOf`, `chosenValueOf`, `withValue`, `withoutValue`;
  `GameSettingKeys` holds the engine's, `flutter3d.pad.look` and its kin),
  and the player's controls are one `ActionMap` (`actions`, `actionsOr`).
  `bindings`, `settings`, `settingOf`, `setSetting`, `setVolume(String)`,
  `savedActions` and `ownedActionMap` are gone; `colorVisionSetting` and
  `highContrastSetting` are `GameSettingKeys.colorVision` and
  `highContrast`, and `ColorRole.setting` is a `SettingKey<int>`.
- **Breaking: the settings file is in the format envelope**, as
  `f3d.settings` version 2 (`GameSettings.format`), with its values under
  `values` and the whole action map under `actions`. A file from before is
  read as version 1: its names move to their namespaced ids (`pad.look` is
  `flutter3d.pad.look`, `colour.<role>` is `flutter3d.color.<role>`) and its
  `bindings` become the map's buttons. A newer file is refused with a
  `GameSettingsFormatException`. `SettingsFile` takes the game's
  `defaultActions`, which a saved map is read against.
- **Breaking: `GameSettingsController` holds the settings and the live
  map.** It takes `settings:` (was `config:`) and the map the devices read
  as `actions:`; `settings` is the current value, replaced on every change
  and handed to `apply`. `setVolume` takes an `AudioBus`; `setSetting` is
  `setValue(SettingKey, value)`, beside `clearValue` and `update`.
- **Breaking: the settings panel is made of `SettingsSection`s.**
  `SettingsPanel(settings:, sections:)` and `SettingsOverlay(settings:,
  sections:, opening:, canOpen:)` replace the dozen arguments (`mixer`,
  `config`, `padConnected`, `defaultActionMap`, `buses`, `credits`,
  `colors`, `privacy`, `actionTuning`, the callbacks); a game passes
  `SettingsSection.standard(...)` or its own list of `VolumesSection`,
  `ControlsSection`, `AccessibilitySection`, `ColorsSection`,
  `ConsentsSection`, `MouseSection`, `GamepadSection` and `WidgetSection`.
- **Breaking: what a pad's sticks do is bindings.** `PadRoutes`,
  `PadStickUse`, `PadStickTarget` and `PadAxisPair` are gone: the left stick
  walks through a `DualAxisBinding` on `pad:stick.left`, the right one looks
  at `PadInput.lookRate`, and `PadInput.addDefaultsTo` adds them (only where
  the map binds nothing already). A driving game calls
  `PadInput.addDrivingDefaultsTo`, which binds the stick's two directions
  (`InputSource.padHalfAxis`) to its steering as buttons with a magnitude.
  `PadInput.storeSettings` is gone; `applySettings` reads `GameSettingKeys`.
- **Breaking: a numbered slot is an action.** `DesktopInput.slotKeys`,
  `defaultSlotKeys`, `PadInput.slotButtons` and `dpadSlots` are gone: a
  button bound to `SlotActions.of(n)` requests slot `n` on its press, the
  number row is bound by `DesktopInput.addDefaultsTo` (and
  `addSlotsTo`), and the d-pad by `PadInput.addSlotDefaultsTo`. A player
  rebinds them like any other action, and the file keeps them.
- **An action's label is a message id.** The rebinding rows say an
  action through `Flutter3dGameLocalizations.actionLabel`, so the engine's
  actions read in the player's language; a game answers its own through
  `ActionBindingsSection.actionLabel` (`ControlsSection.actionLabel`).
- **Breaking: `postGameEvent` is `postToolEvent`, a function.** The
  mutable `GameEventPoster postGameEvent` variable is gone, with
  `postGameEventToVmService`; `GameEventPoster` is `ToolEventPoster` and
  `gameEventPrefix` is `toolEventPrefix`. A test hears what was posted with
  `captureToolEvents` from the new `package:flutter3d_game/testing.dart`,
  which returns the function that stops listening.
- **`GameUiTheme` colours the maps and the touch controls.** New roles
  `mapFloor`, `mapWall`, `mapPlayer`, `mapBackdrop`, `miniMapTrack`,
  `miniMapPlayer`, `miniMapOthers`, `miniMapBackdrop` and `touchTrack`,
  `touchFill`, `touchUnavailable`, `touchOutline`, `touchHeld`,
  `touchPressed`, `touchKnob`, `touchGlyph`, `touchOn`, `touchOnGlyph`,
  each defaulting to the colour the widget had. `AutomapView`'s colours
  are nullable and default to the theme; `TouchButton`, `TouchStick`,
  `TouchToggle` and the touch slots read it.
- **`RunSession`, `RunStatus` and `RunTimeline` document the API** rather
  than the repository's demos.
- **`flutter3d_game` re-exports `flutter3d`**, and from `flutter3d_app` what
  a first game opens a window with: `Flutter3dView`, which opens the device,
  makes the renderer, runs the loop and owns focus and the lifecycle, the
  `Flutter3dEngine` it hands a game, `ViewResolution`, `DidNotStart`,
  `LevelLoader`, `LoadedLevel` and `SharedMeshes`. The example is written
  with two imports and no `hide`, on `Flutter3dView`. The low level under
  the view (`openDevice`, `presentFrame`, `SceneSurface`, `FrameClock`) is
  imported from `flutter3d_app` by a game that wants it. `loadLevelAsset`
  reads a level from the asset bundle.
- **Breaking: one suffix for settings, Settings, and Descriptor in the
  HAL.** `AxisTuning` is `AxisSettings`, `GameConfig` is `GameSettings`,
  `GameSettings` is `GameSettingsController`. Every settings class is
  `final` with a `const` constructor and a `copyWith` over every field; a
  nullable field is reset with `copyWith(clearX: true)`. `dart fix` carries
  the renames.
- **Breaking: `ActorAnimations.events` is the bus.** It is an
  `EventRegistry?`, and each marker is published onto it as an
  `AnimationMarkerPassed`, whose name is `animation.markerPassed`. A game
  that sets it declares the event there once, with
  `AnimationMarkerPassed.codec`; the drained buffer it used to be is gone
  from `flutter3d_sim`.
- **Breaking: a boolean reads as a question, and no `bool` is positional.**
  `Consents.cloud` is `hasCloudConsent`; `Credit.traced` is `isTraced`;
  `Playing.dragLook` is `usesDragLook`; `SaveSync.consented` is `hasConsent`;
  `Autosave.paused` takes `{required bool now}`, and `Consents.answerCloud`
  and `answerTelemetry` take `{required bool granted}`. `dart fix` carries
  the renames.
- **Breaking: one verb per job.** `DragLook.take` is `drain`;
  `ActionMap.takeFrom` and `Bindings.takeFrom` are `copyFrom`;
  `DesktopInput.release` is `releaseMouse`, the other half of `captureMouse`,
  so `dispose` is the only teardown. `RunSession`'s hooks `open` and `close`
  are `loadLevel` and `disposeLevel`: a level comes from an asset and goes
  with a teardown, and neither is a connection. `dart fix` carries the calls;
  a subclass renames its overrides.
- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `BehaviourOverlay` is `BehaviorOverlay`, `BehaviourStatus` is
  `BehaviorStatus`, `centre` is `center`, `colour` is `color`,
  `colourChoice` is `colorChoice`, `colourOf` is `colorOf`, `colours` is
  `colors`, `colourVision` is `colorVision`, `colourVisionChoices` is
  `colorVisionChoices`, `feetBelowCentre` is `feetBelowCenter`,
  `kilometresPerHour` is `kilometersPerHour`, `licence` is `license`,
  `licenceUrl` is `licenseUrl`, `metresAcross` is `metersAcross`,
  `outlineColourOf` is `outlineColorOf`. Only the Dart names changed: a
  file keeps the keys it was written with, and `dart fix` carries the
  renames.
- **`DemoRecording` takes the `physics` it records on** (`Demo.physics`),
  the Dart reference unless handed the one the game chose.
- **Breaking: one input model, the `ActionMap`.** `DesktopInput` and
  `PadInput` take `actions:` and no longer `bindings:`; their `bindings`
  fields are `actions.buttons`. `DesktopInput.defaultBindings`,
  `PadInput.defaultBindings` and `ownedBindings` are gone for
  `DesktopInput.addDefaultsTo(map)`, `PadInput.addDefaultsTo(map)` and
  `ownedActionMap`; `PadInput.knowsPad` takes the map. `Rebinding` edits a
  map only: `start` and `waitingFor` take and answer any kind of action (the
  button-only pair is gone), and `reset` takes the map that shipped.
  `SettingsPanel` takes its controls as a widget (`controls:`, an
  `ActionBindingsSection`), and `SettingsOverlay` takes `defaultActionMap`
  instead of `bindings`, `actions` and `defaultBindings`; what is rebindable
  is what the game's `ActionSet` declares. `SettingsBindingRow` takes a
  label, and naming a source on screen is
  `Flutter3dGameLocalizations.source`.

- **Breaking: `SettingsCubit` is `GameSettingsController`, a `ValueListenable`.** The
  same state machine without a state-management package in the API: listen
  with a `ValueListenableBuilder`, read `value`, `dispose` it. `rebind` takes
  any action and its part (`rebindAction` is gone), `reset` takes the
  action map, and `saved` is the write the last change started.
  `SettingsState.waitingFor` is any kind of action. `flutter_bloc` is no
  longer a dependency.

- **Words in the player's language.** `Flutter3dGameLocalizations` is a
  `LocalizationsDelegate` with English and Russian, and every default string
  of these screens reads it: the settings panel, the rebinding rows, the
  privacy questions, `TapToRestart`, the credits. Without the delegate the
  words are English. **Breaking:** `TapToRestart.label` and
  `CreditsSection.heading` are nullable for it, `CreditsSection.footnote`
  has no default (it named this repository), and `colorVisionChoices` is
  `Flutter3dGameLocalizations.colorVisionChoices`.

- **The screens' colours are a theme.** `GameUiTheme` is a
  `ThemeExtension` with the colours the settings panel and the HUD were
  typed in; without one in the theme they are what they were.

- **Breaking: the documents and the run are asynchronous**, because
  `Storage` is. `SettingsFile.read`, `SaveFile.read`/`readRecord`,
  `DemoFile.read` answer futures; their writes answer `Future<bool>` and
  say a refusal through `onIssue`; `clear` is a future. `RunSession.save`,
  `Autosave.paused` and `Autosave.checkpoint` answer `Future<bool>`.
  `Consents` and `SaveSync` read their answers once (`ready`) and answer the
  questions with `Future<bool>`. Read the settings in `main()` before
  `runApp`.

- **Save slots.** `SaveSlots` hands out a `SaveFile` per slot id and lists
  which hold a run; `SaveFile.slot` names it, and the default slot is still
  `save.json`, so a save written before slots is its run. A cloud copy is
  kept under the slot's own name.

- **Breaking: `CloudSaveStore` is an `abstract base class`** — `extends`,
  not `implements`.

- **Breaking: `cloudServer` and `telemetryPolicy` are gone.** `GameCloud`
  takes `server` (null for none) and a required `policy`: both were the
  engine's constants, one of them read from a `--dart-define` every game
  shared.

- **Breaking: `Playing` is an object the game holds.** `Playing.ofPlatform()`
  asks the platform once; `touch`, `capturesPointer` and `dragLook` are its
  fields, and a test makes the one it means. `configureForTouch` is
  `lockLandscapeForTouch`, an app's explicit choice taking the `Playing`.

- **Breaking: `testing.dart` is gone.** `creditGaps` checked this
  repository's demos against their assets and was never engine API; it
  lives with the demos now.

- **`replayAfterHotSwap` takes `hotSwap` openly**, for an engine with its
  own `HotSwap`; it was marked visible for testing in a public signature.

- **A tool attached to a game asks one extension what the others are.**
  Every `ext.flutter3d.*` extension registers through
  `registerFlutter3dExtension`, and `ext.flutter3d.version` answers the VM
  schema version and their names. `api/flutter3d_game.vm` records each
  parameter's type and the keys each extension answers with.
- **A saved action map says what it is.** `ActionMap.format` (`f3d.actions`)
  writes the format envelope first and refuses another format's document or a
  newer one with the reason, as `ActionMapFormatException`; keys a later
  build wrote are kept and written back (`ActionMap.unknown`). The envelope is
  additive, so the version stays 1.
- **Breaking:** `ActionMap` extends `FormatDocument`, and a newer map throws
  `ActionMapFormatException` where it threw `dart:core`'s `FormatException`.
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

- **Action maps.** `ActionMap` holds a game's declared `ActionSet` and every
  device's way to each action: buttons in the shared `Bindings` table as
  before, and `ActionBinding`s for the rest — `AxisComposite` and
  `DualAxisComposite` (two or four keys as an axis), `AxisBinding` and
  `DualAxisBinding` (a trigger, a stick, the mouse's motion), each with an
  `AxisSettings` of dead zone, sensitivity and invert. `rebind` replaces within
  the source's device and reports `BindingConflict`s, resolved by a
  `ConflictPolicy` (steal, swap or refuse). Saved as versioned JSON; a table
  saved before action maps reads as its buttons. `ActionInput` is the shared
  arithmetic, and `DesktopInput` and `PadInput` take an `actions` map;
  `ownedActionMap` attaches one to a `GameSettings`, which saves its axes under
  `actions`. `InputSource` gains `padAxis`, `padStick`, `touch`,
  `pointerMotion`, `none` and `device`.

- **Rebinding every kind of action.** `Rebinding` and `SettingsCubit` edit an
  action map: `rebindAction` with a composite's part, `setTuning`,
  `resetActions`, and the conflicts a rebind met in `SettingsState`.
  `ActionBindingsSection` is the settings piece, and `SettingsOverlay` shows
  it given `defaultActionMap`. `TouchStick` and `TouchControls` write any
  `DualAxisAction`; `TouchAction.declared` labels a button as its set does.
  `replayDemo` and `replayDemoOnLoop` take the game's `ActionSet` to upgrade
  an old tape.

- **Breaking: `ActionBinding`'s subtypes, `Rebinding`, `SettingsOverlay`,
  `SettingsPanel`, `TouchControls`, `TouchStick`** as the snapshot counts
  breaks: new subtypes of the new sealed `ActionBinding`, a required
  parameter made optional, and new optional fields on widgets. No caller
  changes; see the migration table.

- **`DemoRecording` writes the simulation and a pose record.** `simulation`
  goes into the file, and `bodies`, asked every `poseEvery` steps by
  `observe`, fills `Demo.poses`. `replayDemo`, `replayDemoOnLoop` and
  `rewindBufferFromDemo` take an optional `simulation` and throw
  `ReplayException` for a run recorded on another one, carrying the poses a
  viewer plays instead.

- **The VM service surface is a contract too.** The `ext.flutter3d.timeline.*`,
  `cvar.*` and `level.*` extensions, with the parameter keys each reads, and
  the `flutter3d.timeline.replayedUnderNewCode` event are written down in
  `api/flutter3d_game.vm` and held to the same semver as the Dart API: an
  extension removed, or one that stops reading a key, waits for a major, and
  a new key has to have a default.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#tools-for-agents-are-a-contract-too)
  has the rules.

- **Breaking: `ActorAppearance`, `ActorCorpses`, `ActorGraphs`,
  `FixtureAppearance` and `PadStickTarget` can no longer be implemented
  outside their own library: each is an `abstract base mixin class` now, so a
  game or a test mixes it in (`with`) and its class is `final` or `base`. A
  member added to one in a 1.x release arrives with a body, which an
  `implements` could not have taken without breaking somebody.
  `CloudSaveStore` stays implementable, and says so.

- **The web is declared.** `testing.dart` lists its directory through a helper
  chosen by `if (dart.library.js_interop)`.

- **A recording follows an `EngineLoop`.** `DemoRecording.attach` writes
  the loop's input, each step's event digest and every loop change into the
  run. It starts with the plugins' state, since a recording may begin long
  after the engine did. `replayDemoOnLoop` plays the file back through a
  loop, makes its changes at their steps, and reports the first step whose
  events differ (`DemoReplay.eventDivergence`) beside the first checkpoint
  that does.

- **`postToolEvent` tells whoever watches the game what happened.** It
  posts `flutter3d.<kind>` with a JSON map on the VM service's `Extension`
  stream, where the editor's Play and an agent's `play_events` listen;
  nothing goes anywhere when nobody is attached. A function, not a
  variable anybody can reassign: a test hears what was posted through
  `captureToolEvents` in `package:flutter3d_game/testing.dart`.
  `replayAfterHotSwap` posts its `timeline.replayedUnderNewCode` through it.

- **A high-contrast accommodation.** `Accommodations.highContrast` reads the
  platform's own flag, `highContrastOf` turns the engine's look on from the
  `a11y.highContrast` setting with that flag as the fallback, and the
  settings panel has a High contrast switch that shows what is drawn.
  `ActorVisuals.outlineOf` and `FixtureVisuals.outlineOf` let a game name
  the role colour each actor and fixture is ringed in; `outlineColorOf`
  turns a `Color` into the colour a ring takes.

- **`GameCloud.shares`** is a `RunService` on the same server, using
  `httpRunTransport` over `package:http`. Pressing Share counts as the
  player's yes; no question guards it.

- **The player is asked before anything of theirs leaves the device.**
  - `Consents` holds two questions: may the run be kept in the cloud, and
    may finished runs be sent. Both are no until answered.
  - `PrivacySection` puts both in the settings panel, through
    `SettingsOverlay.privacy`.
  - `askWhichRun` and `syncBeforeBegin` settle two different runs before
    a run begins.
  - `GameCloud` builds the save store and the telemetry uploader from
    `FLUTTER3D_CLOUD`.
  - `httpJsonPost` is a `JsonPost` over `package:http`.

- **`DemoRecording` stamps the run's physics** into the demo it writes.

- **Gestures reach the graph.** `ActorAnimations.gesture` fires the
  trigger `cue:<name>` on the actor's graph, made now if it is not yet, for
  its state machine to play; a graph with no such trigger gets nothing.

- **Colours with meanings a player can move.** A `ColorRole` is what a
  colour is for, what the panel calls it and what it is by default;
  `ColorRoles` gives each the player's choice from `colour.<name>` — its
  own colour or one of Okabe and Ito's eight, which stay apart for every
  common kind of colour blindness — and lints the roles seen together in
  the colours the player has them. `SettingsPanel(colours:)` and
  `SettingsOverlay(colours:)` add a Colours section, a row of swatches
  per role (`SettingsColourRow`).

- **The player picks a colour vision correction.** The settings panel's
  Accessibility section has a Colour vision choice — off, protan, deutan,
  tritan — written to `a11y.colorVision`; `colorVisionOf` reads it as a
  `ColorVision.correct`, and `ColorVisionLook` hands a frame the table for
  it, made once per kind, keeping a look's own table where it has one.
  `SettingsChoiceRow` is the panel's row of named choices.

- **Graphs made on an actor's first step.** `ActorAnimations(graphFor:)`
  makes an actor's graph inside the step it first takes, so monsters
  spawned as a level goes get one at the same step in every run. A
  restore makes again the graphs a snapshot has and drops those it does
  not. `write` now takes the graph, so a game sets its goals' targets as
  well as its parameters. `ActorVisuals(simulated:)` draws such an actor
  in the pose its graph was left in by the last step and makes no graph
  of its own for it.

- **Animation graphs stepped by the simulation.** `ActorAnimations` is
  an `ActorStrides`. It steps each attached actor's graph on the fixed
  step, writing the brain's decisions into its parameters first. A graph
  with a root node walks the body by its root motion, turned the way the
  actor faces and scaled by the model's size, so a wall stops it. Each
  marker it passes arrives as an `AnimationMarkerPassed` game event, in
  order with that step's shots and deaths. `save` and `restore` carry
  every graph by its actor's ordinal, and a run restored mid-walk steps on
  to the same place and the same footfalls.

- **`ActorGraphs.dress` and a richer `drive`.** `dress` gets each
  graph once it is built, with the model, to add goals or layers. `drive`
  gets the graph and the model every frame, so a goal's target can be put
  in the model's space.

- **`ActorVisuals.markersPassed`**: every marker an actor's graph passed
  in the last `animate`, with the actor and the state. The dungeon plays
  a monster's footsteps from them.

- **A modelled actor can be animated by a graph.** `ActorVisuals` takes
  `graphs:`, an `ActorGraphs`. For each modelled actor it gives a machine
  for, an `AnimationGraph` is built over the model's own clips and
  `Pose.fromNodes` of its nodes. Once a frame `drive` writes what the actor
  is doing into the graph's parameters, and the evaluated pose goes into
  the model's targets. The machine's states, transitions, fades and exit
  times decide what is drawn, where before only a list of clip names did.
  An actor given no machine keeps its clip names. `graphOf` and `modelOf`
  say what an actor is animated by and drawn as. A dead actor's ragdoll
  still takes over first.
- **A dead monster can fall as a body.** `ActorVisuals` takes
  `corpses:`, an `ActorCorpses`. The moment a modelled actor is seen dead,
  its `begin` is asked whether to take the pose over, and is given the
  joints' world matrices from the frame before so the body keeps its
  motion. From then on the actor's clip is not played on and its model is
  not moved, and `step` writes its joints once a frame. `remove` and
  `dispose` reach it too. Without one, the death clip plays as before.
  This package names no physics: the dungeon hands it a ragdoll.

- **An edit made under a running game goes into its demo.**
  `DemoRecording` is the run being written down: start, recorder,
  checkpoints and the levels swapped in, with `levelSwapped` turning the
  timeline's step into one on this tape and dropping what the swap lived
  again. `LiveLevel(swapped:)` hears the step the timeline swapped at, before
  `present`. `replayDemo` plays a `Demo` from its start, swaps each level in
  where the tape reaches it and compares the file's checkpoints by step.
  `rewindBufferFromDemo` refuses a demo with swaps, since a keyframe before a
  swap belongs to the other level.
- **`ext.flutter3d.level.patch` takes an edit instead of a whole level.**
  `registerLevelExtension` registers it beside `level.apply`;
  `answerLevelPatch` applies a `LevelPatch` to `LiveLevel.level` and passes
  the patch's own diff to `applyWhenReady(diff:)` and `apply(diff:)`. A
  patch made against another version is answered with
  `LevelPatch.staleCode`, which tells the sender to send the whole level; a
  patched level that does not build is refused as an ordinary error.
- **`BehaviorOverlay` draws what every tree last decided**: a stroke per
  node on the running path above each actor, coloured by how it came out, and
  a line to where its leaf is taking it; `describe()` gives the same path by
  name. It reads boards and never makes one, so switching it on cannot change
  a snapshot.
- **`RunTimeline` scrubs without cutting.** `scrubTo` moves the live state
  to a held step while paused and keeps the tape and the present;
  `returnToPresent` puts the present back exactly, `branchHere` cuts the
  future at the scrubbed step and stays paused, and `stepOnce` from a scrub
  walks the tape. `resume` from a scrub resumes at the present. `tracks`
  replays the buffer into `EntityTracks` and puts the live state back.
  Refusals come back as `ScrubRefused` with a reason.
- **`registerTimelineExtensions`** adds `scrubTo`, `returnToPresent`,
  `branchHere` and, with an `entityLayout`, `tracks`; `status` answers the
  present step, the oldest held and the scrub.
- **`Autosave` writes the run on the way into a pause, at a checkpoint and
  when the application goes to the background**, which on a phone is the
  only warning before the process is ended. `SaveFile` skips a write of the
  run it last wrote, so a menu opened and closed costs nothing.
- **`SaveFile` takes a `SaveSchema`** and migrates older saves on the way in;
  a save now carries its schema, its step and its digest. `readRecord`,
  `parse`, `writeRecord` and `encode` are for copies kept elsewhere.
  `RunSession.stepOf` says how far a run has got, and `save` returns whether
  it wrote.
- **`SaveSync` keeps a save in the cloud, and sends nothing until the player
  agrees.** Consent is off on a fresh install and is kept in a document of
  its own; without it no store is called. Conflicts are settled by
  `resolveSaves`; two equal runs come back as `SyncOutcome.ask` for the
  player, and a cloud save from a newer build is left alone. Stores:
  `HttpCloudSaves` (`GET`/`PUT` with `ETag` preconditions) and
  `PlatformCloudSaves` for Play Games and iCloud over the
  `flutter3d/cloud_saves` channel. Every failure is an answer, not a throw.

- **`replayAfterHotSwap` asks the question a hot reload leaves open on its
  own.** After every `HotSwap` it lives the last seconds again under the new
  code and says whether they came out the same or where they parted, in the
  console and as a `flutter3d.timeline.replayedUnderNewCode` VM service
  event. Returns the call that stops it.
- **A level that has to be built before it can be swapped in.**
  `LiveLevel(prepare:)` is awaited by `applyWhenReady`, which the extension
  now calls, before anything changes; a level whose `prepare` throws is
  refused with what it threw and the game keeps the one it had.
  `answerLevelApply` returns a `Future`. `LiveLevel.level` is settable, for a
  game that moved to another level by its own means.
- **`RunSession.replaceLevel` puts a new build of the level being played in
  its place** and carries the run over through the game's own `snapshotOf`
  and `restoreInto`, without loading anything or starting the level again.

- **`RunTimeline.replayUnderNewCode` shows what a code reload changed.** It
  lives the last seconds again under the new code from the nearest keyframe,
  compares the state at each keyframe the old run left and at the present,
  and names the first field that parted and the two steps it parted between.
  The replay is kept and the buffer rebased there.
- **`registerTuningExtensions`** puts `ext.flutter3d.cvar.set` and
  `cvar.list` on the VM service; a set goes through `InputState.tune`, so it
  lands on the tape. `registerTimelineExtensions(capture:)` adds
  `ext.flutter3d.timeline.replayUnderNewCode`.

- **`LiveLevel` takes a level edited under a running game.** The game hands
  it `present` and `rebuild`; `apply` patches the look in place and sends the
  simulation's half through `swapLevel`. `registerLevelExtension` puts it on
  the VM service as `ext.flutter3d.level.apply {document, hash}`, which the
  editor calls after a save; a document whose digest does not match its hash
  is refused.

- **`RunTimeline.swapLevel` replaces the level under a running game without
  the run jumping.** It restores the last keyframe, lets the caller swap the
  level, replays the recorded input to the present with the devices muted,
  and rebases the buffer there. `TimelineLevelSwapped` records the step and
  the level's digest, so a replay that swaps at the same step arrives where
  the run did.

Its `flutter3d_*` dependencies ask for `^1.0.0`, and it asks for `pad_input` and `pointer_lock` `^0.5.0`.

## 0.8.1

**Volumes without SoLoud.** The settings panel names buses and nothing else of
audio, and it reached them through `flutter3d_audio`, which brought
`flutter_soloud` and a native build that needs a newer Flutter than 3.44. It
now depends on `flutter3d_audio_core`, the same `Mixer`, `AudioBus` and
`SoundDef` without a backend; `flutter3d_audio` re-exports them, so a game
that plays sound passes its mixer in as before.

**Either `flutter_bloc`.** It takes 8.1.2 as well as 9, which the settings
cubit compiles and passes its tests against, so a workspace that still has a
package on 8 resolves. The Dart and `vector_math` constraints are relaxed as
for the rest of the stack.

## 0.8.0

**Moves with the stack to 0.8.0**, whose `flutter3d_hardware` changes
`PassEncoder.bindTexture` to return `bool` and makes every backend forget its
bindings at `bindPipeline`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.2

**Two triggers on one action answer with the harder press.** The value was
whichever trigger `PadInput` read last, so 1.0 on the left and 0.2 on the right
gave a throttle of 0.2. Letting one go also withdrew the value the other had
just written, and for that frame the action fell back to its held 1.0. The
action now takes the largest magnitude among the controls pressing it, and is
withdrawn only when none is.

## 0.7.1

**A restart chosen while the next level was loading stays a restart.**
`RunSession.advance` loaded the next level on top of it and saved that.
`TouchButton` releases the action it pressed, not whatever it holds at
pointer-up, so a relaid-out button list no longer leaves an action held for
good. `PadInput` tracks analogue state per control, so two triggers bound to
one action stop cancelling each other.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3, `vm_service` ^15.3.0.

## 0.7.0

**Breaking.** Everything a game adds to an application is here, and
`flutter3d_sim` is no longer re-exported. `flutter3d_session`,
`flutter3d_screens` and `flutter3d_bridge` are marked `discontinued` on pub.dev
the day this is published, the last two with this package as their
replacement; `doc/boundary-0.7.0.md` has the whole list.

* From `flutter3d_session`: `RunSession`, `RunTimeline` and its service
  extensions, the demo timeline and the bug-report tape, the settings overlay
  and panel, rebinding, `SaveFile`/`SettingsFile`/`DemoFile`, volumes, credits,
  `AutomapView`, `DragLook`, `TapToRestart`, `clockText` and
  `configureForTouch`. `package:flutter3d_game/testing.dart` holds
  `creditGaps`. At 0.6.0 everything in that list after the bug-report tape was
  `flutter3d_screens`, which was folded into the session first and followed it
  here.
* From `flutter3d_bridge`: `ActorVisuals`, `FixtureVisuals` and
  `SoundOcclusion`. Loading a level into a scene, `LevelLoader` and what it
  stands on, went to `flutter3d_app`.
* To `flutter3d_app`: `Issue`, `IssueSink` and `IssueLog`, which storage
  reports through. This package depends on `flutter3d_app`, and a file that
  used one of the three imports it.
* **Breaking. A file that steps a simulation imports `flutter3d_sim` by
  name.** The line `export 'package:flutter3d_sim/flutter3d_sim.dart'` is gone
  from this library, so `Level`, `GameLoop`, `InputState` and every other
  simulation type stop arriving through it. `flutter3d_sim` is still a
  dependency here at `^0.7.0`; a package that uses its types adds it to its own
  pubspec.
* **`RunTimeline`: a running game paused, stepped and rewound from outside.**
  New since 0.6.0. `pause`, `resume`, `stepOnce`, `preview(secondsAgo)`,
  `releaseAt` and `releaseAtStep(step)` over a `RewindBuffer`, with each action
  kept as a sealed `TimelineCommand`: `TimelinePaused`, `TimelineResumed`,
  `TimelineStepped` or `TimelineBranched`. `registerTimelineExtensions` puts a
  timeline on the VM service as `ext.flutter3d.timeline.pause`, `resume`,
  `stepOnce`, `preview`, `releaseAtStep`, `history` and `status`, with
  `frameTimes` and `bugReport` when the caller supplies them. That is the
  channel a tool attached to a running game already has.
  `rewindBufferFromDemo` replays a whole `Demo` once into a buffer that reaches
  every step of it, and `bugReportTape` answers the state and the tape of the
  last seconds a `RewindBuffer` kept, or null before its first keyframe.
* **`LevelWalk`, `OpenKind` and `openRegistryFor`**, out of the game example's
  `main.dart`: a body that walks a level, turns where it is dragged and carries
  a camera at eye height, and a registry that accepts every type a level names
  before a game has taught it any.
* **A level names a model by either kind of path.** `FixtureVisuals` and
  `ActorVisuals` load through the engine's `loadModelByPath`: a model a level
  names under `assets_src/` is read from the `.f3d` the build hook converted
  it into, and any other path from the bundle exactly as before, so a project
  that has run `dart run flutter3d_build:init` and one that has not both load
  through the same two classes.
* **What it depends on.** `flutter3d_app`, `flutter3d`, `flutter3d_sim`,
  `flutter3d_audio` and `flutter3d_particles` at `^0.7.0`, `flutter_bloc` for
  the settings cubit, and `pad_input` and `pointer_lock` at `^0.4.0`. None of
  them is re-exported. The input devices, the bindings, the touch controls and
  `GameConfig` are what 0.6.0 had.

## 0.6.0

* **A floor, and no code — the same shape as 0.5.1 and for the same reason.**
  The input devices, the fixed step and the interpolation are byte for byte
  0.5.1's. What moved is the promise about the package this one re-exports
  whole: `flutter3d_sim` is required at `^0.6.0`, so a caller reaching a
  simulation type through this name reaches a version that has it rather than
  whatever the resolver picked.
* `pad_input` and `pointer_lock` stay at `^0.4.0`. They are on a line of their
  own, their 0.4.1 is a documentation patch, and a floor that demanded it would
  be claiming this package needs something it does not.

## 0.5.1

* **A floor, and no code.** Nothing in this package changed; what changed is
  what it promises about the package it re-exports. `flutter3d_sim` is now
  required at 0.5.2 or above, because that is where `Heightfield` arrived and,
  through it, `flutter3d_physics` 0.5.1 with the collision shape a body stands
  on. A caller reaching those names through this one was reaching whatever the
  resolver happened to pick, which for a `^0.5.0` floor could be a version
  without either — and the symptom is a compile error in somebody else's
  package.

## 0.5.0

**Breaking.** A stick use carries what it does, and an issue is an object.

* **`PadStickUse` is open, and its interpreter opened with it.** It was an enum
  switched over in one method, so a game could not say its stick leans the
  ship. A use now *is* what it does with a deflection — `route` against a
  narrow `PadStickTarget`, `letGo` for whatever it writes — and the three built
  in are instances rather than cases. There is no switch left to break.
* **`IssueSink` takes an `Issue`.** A bare string could not grow a severity or
  a source without breaking every sink anybody had written.

## 0.4.1

* **The simulation moved out, and nothing that imports this package changes a
  line.** The fixed step, the entity store, the level format, saves, demos, the
  rewind buffer, actors, navigation and the maths are `flutter3d_sim` now — a
  plain Dart package with no Flutter in it, so a server can replay a run
  through the same simulation the player ran. This package keeps the eight
  files that reached Flutter — the touch stick and button, keyboard and mouse,
  the gamepad route, the `MediaQuery` read and the diagnostics sink — and
  re-exports `flutter3d_sim` and `flutter3d_physics` whole.

## 0.4.0

* **A touch control lets go when it leaves.** The button and the stick press
  into a shared `InputState`, and unmounting while pressed is a normal path —
  settings opening over the control, a level transition. Each now releases its
  held action or zeroes its axis in `dispose` instead of leaving the runner
  jumping into the next screen.

## 0.3.0

* **`Playing` no longer asks `kIsWeb`,** and both answers it used to give about a
  browser were wrong. Capture is asked of `pointer_lock`, which can now hold a
  pointer in a desktop browser and says so — and which says no on Windows and
  Linux, where the old platform list claimed a capture that does not exist and
  then turned off drag-look, leaving a camera that could not move at all. Touch
  is asked of `defaultTargetPlatform`, which reports a mobile browser as
  `android` or `iOS`, so a phone opening a web build finally gets the on-screen
  controls it has always had natively.
* `InputTape` records a run as transitions plus axes, one entry per fixed step,
  and replays it exactly. A tape of intents, not of poses.
* `StepSystems`: a game adds a rule to a genre's step without forking it.
  Phases are named by the genre, announced unconditionally, and run in a
  defined order — never in whatever order a hash map returns.
* `InputState` exposes this step's presses, releases and analogue readings,
  which is what a recorder needs and cannot ask for by name.

## 0.2.0

* An ECS whose every component serialises, and one snapshot mechanism serving
  the save, the network packet and the determinism test.
* Actors with a flow field to walk it, mechanisms composed through signals, and
  movers that carry what stands on them.
* A pad and a touch layer that arrive as the same actions a key does, and
  `GameAction` opened from an enum to a value class so a genre can invent its
  own.
* `WorldStep`: the order the world is stepped in, as named phases the game
  calls, because two genres want their actors on different sides of the index.

## 0.1.0

* A fixed timestep with an accumulator that reports the steps it had to drop,
  and interpolation at draw time.
* Device-independent input: actions, bindings, and a keyboard — all arriving as
  the same thing.
* Levels as documents — brushes, entities, lights, materials — with a validator
  that reports a coordinate rather than "the file is broken".
