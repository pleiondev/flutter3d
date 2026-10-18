## 1.0.0-rc.1

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
