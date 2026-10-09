## 1.0.0-rc.1

- **Breaking: `soundtrack.dart` does not re-export the sound types.**
  `AudioBus`, `Heard`, `SoundBank` and `SoundDef` are
  `flutter3d_audio_core`'s, and `flutter3d_audio` names them too.

- **`Daylight`'s sun is in lux.** `Daylight.defaultSunIntensity` is 2.6 ×
  `Photometric.legacyUnit`, about 15 000 lux; it was left at 2.6 when lights
  moved to lux, a sun two-thousandths of daylight.
- **A best run is a format of its own: `f3d.ghostTape`.** `tapeToJson`
  writes the envelope (`ghostTapeFormat`), and `tapeFromJson` reads it and
  the bare `{"version": 1}` every best run had before; another format's
  document or a newer one throws a `DocumentFormatException`. Not
  `f3d.ghost`, the racing lap's id, whose body is a different one.

- **New: one package for what was five.** `flutter3d_addon_reactions`,
  `flutter3d_addon_soundtrack`, `flutter3d_addon_ghost`,
  `flutter3d_addon_seeded_levels` and `flutter3d_addon_world` are libraries
  of this package now: `reactions.dart`, `soundtrack.dart`, `ghost.dart`,
  `seeded_levels.dart` and `world.dart`, each with the API its package had,
  and `flutter3d_game_kit.dart` exports them all. `dart run
  flutter3d_build:migrate` moves a project's dependencies and imports; the
  packages' own histories are in `doc/changelogs/`.
- **No native code.** The ragdoll, the wrecks and the party sessions, which
  reach the physics core in C, are `flutter3d_game_physics`, and so are
  `ElementSounds`, `ElementCues` and `Daylight.lightWater` (now the
  `DaylightOnWater` extension), which reach it through `flutter3d_effects`.
  A game that uses only the parts here compiles no C and downloads no
  wgpu-native. `migrate` moves the dependency and the imports.

### `reactions.dart`, from `flutter3d_addon_reactions` 1.0.0-rc.1

- **Breaking: `ReactionsPlugin.take` is `drain`**, the verb for a read that
  empties what it reads.
- **A reaction a game can grow.** `ReactionEffect` is an open base for what
  `Reaction` has no field for — slow motion, a rumble, a flare — added by a
  rule with `ReactionBuilder.add`, read from `Reaction.effects` and done by
  `Reaction.perform`. A sixth kind of effect no longer needs this package.

- **What an event looks and feels like, as a decision.** `Reaction` holds
  bursts, lingering plumes, camera jolts, sounds, haptic pulses and whether
  the screen flashes, so a test can assert what a step showed without a
  device. `showIn` and `feel` perform it on a particle system and a camera
  rig.

- **Keyed by event type.** `ReactionTable` runs a game's rules over its
  events in the order they happened, and `ReactionsPlugin` hears it from the
  engine's bus on the frame channel, as a view plugin on plugin API 1.0. A
  step a rollback ran again is not shown twice.

- **The camera's three verbs and the flash.** `Felt` describes a kick, a
  shake or a widening, applied to a `CameraRig`, whose motion setting
  still decides how much. `ScreenFlash` fades by the step and is fired at
  the player's own brightness, so a flash on every hit stays the player's
  choice.

- **Out of three games.** The dungeon, the platformer and racing each had a
  `Reaction` of their own. They use this one now, and keep only the part
  that says which of their events shows what.

### `soundtrack.dart`, from `flutter3d_addon_soundtrack` 1.0.0-rc.1

- **A cue sheet keyed by events.** `CueSheet` keeps what each event sounds
  like and hands back `Heard`s in the order the events happened, so a test
  can ask what a step sounded like with no device. `SoundtrackPlugin`
  hears it from the engine's bus on the frame channel and plays it, as a
  view plugin on plugin API 1.0; a rollback does not play a sound twice.

- **Footsteps by distance.** `Footsteps` pays for a step in metres walked
  across the ground, and none in the air, so a sprint is the same walker
  faster rather than a different one.

- **Sounds with a lifetime.** `Sustained` begins, follows and ends a voice
  by one key, and `SustainedVoices` plays them, so a door grinds for as
  long as it moves and a level change stops what no end will reach. `Voice`
  is an open value class.

- **The elements heard.** `ElementSounds` holds a voice to every fire and
  every fall of water `PhysicsHearing` reports and plays each splash, from
  `ElementCues` a game chooses; `ElementCues.near` is the effects package's
  own recordings.

- **A soundtrack plays on the bus it is given.** `SoundtrackPlugin(bus: ...)`,
  `ElementSounds(cues, bus)` and `SustainedVoices(bus: ...)` play their cues
  on that bus. Leave it out and each sound keeps its own. The sheet is heard
  on the frame channel before the frame phases run, so `AudioPlugin` mixes a
  cue in the frame it was heard. `AudioBus` is exported here, so a sheet can
  name a bus without also importing `flutter3d_audio_core`.

### `ghost.dart`, from `flutter3d_addon_ghost` 1.0.0-rc.1

- **`ghostOfRun` takes the `physics` the ghost is replayed on.**
- **Breaking: `ghostOfRun` answers a `GhostNote`, not an English
  sentence.** The record's `says` is `note`, an open set of ids with what
  each carries; `GhostNote.say(languageCode)` words it in English or Russian
  at the screen.

- **Breaking: `BestRun.load` is asynchronous**, because `Storage` is.
  `BestRun.saved` is the write `finished` started.

- **One ghost for every game.** `Ghost` puts a node where a `Tape` was at a
  moment of it and hides it outside the track. It stands on a model's floor,
  turns by its facing and lifts along the track's own up, so the same class
  draws a runner on its feet and a car leaning into a banked corner.

- **A ghost is a look, not a livery.** `Ghost.look` is translucent, unlit and
  writes no depth; `Ghost.haunt` puts it on every part of a model, replacing
  the materials rather than editing them; `Ghost.build` makes a ghost of the
  game's own model, or of a fallback while that loads.

- **A shared run is raced from its tape or its poses.** `ghostOfRun` plays the
  tape again through the game's own staging when the run can be replayed, and
  reads the body's track off the run's pose record when it cannot: other
  physics, another simulation version, a level edited as it went. A run in
  another version of the level is refused, with the reason.

- **The best run, kept.** `BestRun` samples every run, keeps one only when it
  beats the record on disk (not the session's), refuses a run with almost no
  samples in it, and never throws on a document that will not read. The
  game may name its own document format.

- **Out of the demos.** The platformer's runner ghost and the racing demo's
  ghost car and lap keeper moved here; each demo keeps its own staging, its
  own model and its own file.

### `seeded_levels.dart`, from `flutter3d_addon_seeded_levels` 1.0.0-rc.1

- **Levels made from a seed when they are reached.** `SeededLevels` names a
  level `generated:<seed>` where a level would name its asset, reads the seed
  back with `seedOf`, and makes the document with `level`, off the drawing
  thread. The same seed makes the same level, so a save opens it again and a
  run through them replays.

- **Each level names the next.** The level made from a seed carries `next`
  as the following seed, so a game makes only the levels a player reaches.
  The rules are asked for by depth from the run's first seed, which is how
  they get harder on the way down.

- **From the dungeon demo's depths.** The rules stay the game's: what a room
  holds is its own business, and the dungeon's `Depths` is now its rules
  over this.

### `world.dart`, from `flutter3d_addon_world` 1.0.0-rc.1

- **Breaking: `Horizon.addTo` takes `RenderMaterial`s.** The engine's
  `Material` is `RenderMaterial` in 1.0, so it no longer collides with
  Flutter's; `dart fix` renames it.

- **The hour of the day, on the physical sky.** `Daylight` moves the sun
  round one great circle a day and hands the renderer a `SkySettings` with
  the sun where the hour puts it: the air scatters the morning pale, the
  evening red, and lets the stars out at night. The sun and the moon are lit
  by what the air leaves of them, and only the one in the sky casts the
  shadows. The length of an hour, the sun's strength, the moon's share and
  where noon stands are a game's to set.

- **The world going on to the horizon.** `Horizon` builds rings round the
  simulated square, close at the edge and kilometres apart further out: a
  far floor that starts where the game's ground leaves off and sinks to a far
  depth with a slow swell in it, and a level surface over it carrying the
  depth under it, as a water look reads it. The ground function stays the
  game's; this asks it for heights.

- **Two pieces in one package.** Both dress the world around the part a
  game simulates, and each is a single class; two packages of one class each
  would cost a reader more than they save. They came from the sandbox demo's
  day and night and the Reef demo's open sea.
