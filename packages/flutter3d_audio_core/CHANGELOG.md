## 1.0.0-rc.1

- **Reads the world's air from `flutter3d_matter`** rather than through the
  physics: `WorldProperties` and `standardSpeedOfSound` are what a world is
  made of, and the mix needs no collision world.

- **`EqualPowerPanner.inWorld`**: a Doppler shift reckoned against the
  world's speed of sound, which follows its air's temperature.
- **Docs**: the Doppler rate is `(c + f·v_listener) / (c − f·v_source)`,
  each speed toward the other, as the code computes it; `InverseRolloff`
  stops at `maximum` rather than fading to nought there.
- **Ears and sounds placed in the world.** `AudioListener.placeAt` and
  `AudioEmitter.placeAt` take a `WorldPosition` and the origin the mix is
  relative to, the scene's origin for a game that draws one, and subtract
  in doubles. A listener's and an emitter's `position` stay float32 offsets
  from that origin, as the units contract asks. `Flutter3dView`'s
  `onListenerMoved` is one line: `listener.placeAt(at, forward, origin:
  scene.origin)`.
- **Doppler hears a listener and an emitter placed by hand.** `placeAt`
  used to leave `velocity` alone, so a game driving the ears from
  `onListenerMoved` never heard a shift. The velocity is now how far the
  placements moved it between two mixes over the mix's `dt`; the first
  placement and one with `teleport: true` measure nothing, a `velocity:`
  given outright wins for that mix, and one not placed again before a mix
  has stood still.
- **A sound started while the backend is paused waits for the resume.**
  It used to play at once, over the pause menu. `AudioBackend.pause` now
  says a voice started during it is held from its first sample;
  `SilentBackend` holds it (`SilentVoice.isPaused`), and so does the SoLoud
  backend in `flutter3d_audio`.
- **No Flutter.** The package never used it; it is plain Dart now, and its
  tests run under `dart test`. `SilentBackend` records `isPaused` and
  `isDisposed`.
- **Breaking: a boolean reads as a question, and no `bool` is positional.**
  `SilentVoice.alive` is `isAlive`. `dart fix` carries the renames.
- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `centre` is `center`. Only the Dart names changed: a file keeps
  the keys it was written with, and `dart fix` carries the renames.
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

- **Breaking: `SoundEmitter` is now `AudioEmitter`.** The name says it is the
  scene's emitter of any sound, not just the effects bus's.
  `AudioScene.emitters` and `AudioScene.play` return `AudioEmitter`, and
  every member of `SoundEmitter` lives on `AudioEmitter`. The old name is
  not kept as a typedef: a second name for one type is a second thing to
  document and deprecate, and `dart fix` renames every use.

- **The units are written down.** `units.dart` says what every number in the
  package is measured in: metres, metres per second, seconds, hertz,
  radians, linear gain, and decibels for levels. `decibelsToGain` turns a
  level into a gain, with `silenceDecibels` as the floor that a snapshot can
  still blend through. `speedOfSoundInAir` is read from
  `flutter3d_physics`' `standardSpeedOfSound` rather than being written
  again here.

- **Spatial rendering is a seam.** `SpatialRenderer` turns a listener and an
  emitter into gain, pan, muffle, a doppler rate, distance, azimuth and
  elevation. `EqualPowerPanner` is the panning the scene always had, with the
  same arithmetic, plus azimuth and elevation and doppler that is off by
  default. `AudioScene(spatial: ...)` takes another renderer.

- **Emitters and the listener follow a node.** `PoseSource` is a function
  returning a world matrix. `AudioScene.attach`, `play(follow: ...)` and
  `AudioListener.follow` read it every mix, and velocity for doppler comes
  from the movement between mixes.

- **The mixer grew a desk, and the sliders did not move.** Buses route into
  buses (`setParent`). Each bus has four effect slots (`LowPassEffect` works
  on every backend, `ReverbEffect` on one that mixes buses itself).
  `MixSnapshot`s blend in and out in decibels and add up, and `DuckRule`s
  push one bus down while another is loud. None of it touches
  `Mixer.setVolume` or `toJson`. With none of it configured, a voice's gain
  and muffle are what they were.

- **`AudioPlugin` mixes once a frame** in the loop's `audio` phase. It is a
  view plugin that uses real seconds, so a "paused" snapshot still blends
  while the game is paused.

- **Backends opt in to more.** `MixingBackend` is handed the bus tree to mix
  itself, and `DirectionalBackend` is handed each voice's `SpatialResult`
  for HRTF or propagation. They sit beside `AudioBackend` rather than inside
  it, so no backend written against 1.0 has to change.

- **A sound's bus can be chosen where it plays.** `play(bus: ...)`,
  `HeldVoices(bus: ...)` and `SoundBank.buses` take or report the bus.

- **Breaking: `AudioBackend` is an `abstract base class`**, extended rather
  than implemented, so a member added in a minor release can arrive with a
  body. It gains the device's lifecycle with bodies that do nothing:
  `open`, `pause`, `resume` and `dispose`. `MixingBackend` and
  `DirectionalBackend` are capabilities on their own now rather than
  `AudioBackend`s: a backend `extends AudioBackend implements
  MixingBackend`. `SilentBackend` extends it.

**Moves with the stack to 1.0.0**, whose `flutter3d_hardware` gives
`PassEncoder.draw` a window of the bound indices and every `PassEncoder`
`setAlphaToCoverage`.

Its `flutter3d_*` dependencies ask for `^1.0.0`. It now depends on
`flutter3d_plugin_api`, for `AudioPlugin`, and on `flutter3d_physics`, for
the world's speed of sound.

## 0.8.0

**The half of `flutter3d_audio` that makes no noise.** `AudioScene`, the
`Mixer` and its buses, `SoundDef`, `SoundBank`, `EngineSound`, the listener
and the attenuation curves, with `AudioBackend` as the seam a backend fills.
It is the code `flutter3d_audio` 0.8.1 shipped, moved rather than changed, and
`flutter3d_audio` re-exports all of it, so a type is the same type whichever
package names it.

It exists so that a package which only names a bus or a sound need not carry
SoLoud. `flutter3d_game` offers volume sliders and nothing else of audio, and
through `flutter3d_audio` it brought `flutter_soloud`, whose native build asks
for `hooks` 2.2, which needs a newer `meta` than Flutter 3.44 pins: a game on
Flutter 3.44 could not depend on it at all.
