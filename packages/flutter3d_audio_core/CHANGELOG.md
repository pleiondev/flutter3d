## 1.0.0-rc.1

- **Breaking: `AudioListener.right` is a public `final` field.** The
  listener derives it whenever it is aimed and refreshes it in place, so it
  is live state and says so by its shape; a read compiles as before.
- **Breaking: results that were records are final classes.**
  `EqualPowerPanner` answered or held a record, which can never gain a
  field. Each answers a final class now, with the record's field names (a
  positional `$1` has a name of its own), `==` and `hashCode`. A field read
  compiles as before; a destructuring pattern names the class, and
  `flutter3d_build:migrate` rewrites the `$1` reads.
- **Breaking: `AudioPlugin` is `flutter3d_audio_core`** by default, the
  package that ships it, where it was `flutter3d_audio`, the name of the
  SoLoud package. A run recorded under the old id reads as naming the new
  one.
- **Breaking: a backend's calls take one context each.**
  `AudioBackend.start` takes a `VoiceStart` (new) and `update` a
  `VoiceUpdate` (new); `MixingBackend.routeVoice` and `mixBus` take a
  `VoiceRoute` and a `BusMix`, and `DirectionalBackend.placeVoice` a
  `VoicePlacement` (all new). Their fields are the old parameters. The
  scene owns one of each and sets it before every call, so a mix allocates
  none; a backend reads it during the call and does not keep it. A
  parameter added later would have broken every backend written against
  1.0; a field added to a context breaks none.
- **A scene mixes in a world: `AudioScene.world`.** The constructor takes
  `world:`, the field is settable for a level that brings its own air, and
  the standard world is the default. `SpatialQuery.world` hands it to the
  renderer each mix.
- **The default panner reckons Doppler against the scene's world.**
  `EqualPowerPanner.speedOfSound` is null unless the panner was pinned to a
  world (`EqualPowerPanner.inWorld`) or given a speed, and
  `speedOfSoundIn(world)` says which speed a shift is reckoned against. In
  the standard world it is `speedOfSoundInAir` to the bit, so nothing a
  room's game hears has changed; a cold world's sounds shift further.
- **`MixingBackend` and `DirectionalBackend` are `base mixin class`es with
  bodies that do nothing.** A backend opts in with `extends AudioBackend
  with MixingBackend`, not `implements`, and a member added in a minor
  arrives with a body instead of breaking it.
- **Breaking: `SilentVoice` takes named arguments** (`id:`, `asset:`,
  `gain:`, `pan:`, `rate:`, `loop:`); `SilentBackend` is what makes one.

- **Breaking: `AudioListener.placeAt` and `AudioEmitter.placeAt` require
  `origin`.** It defaulted to the world's origin, which was right only until
  the loop moved its own; then every sound was heard from where the camera
  had been. Pass the scene's origin (`ListenerPose.origin` from
  `Flutter3dView.onListenerMoved`, `Scene.origin` otherwise).

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
