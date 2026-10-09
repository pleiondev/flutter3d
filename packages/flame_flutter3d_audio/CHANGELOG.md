## 1.0.0-rc.1

- **Breaking: `AudioSceneComponent.opener` returns `Speakers`.** The
  `OpenedSpeakers` record is gone; an opener throws `AudioDeviceException`
  for no device, as `openSpeakers` does, and the next `open` asks again.
- **Breaking: `close` is `dispose`**, the teardown verb: it stops every
  sound and disposes the speakers, and `open` does nothing after it.
- **Breaking: a pause holds the voices.** `pause` and `resume` go through
  `AudioBackend.pause` and `resume`, so every voice goes on from where it
  was, and the player's master volume is no longer set to nought under the
  pause.
- **Breaking: a boolean reads as a question, and no `bool` is positional.**
  `SoundEmitterComponent.playing` is `isPlaying`. `dart fix` carries the
  renames.
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

- **The mix is told how long the frame was.** The component passes Flame's
  `dt` to `AudioScene.update`, so mix snapshots blend, ducking attacks and
  releases, and emitters that follow a node get a velocity for doppler. The
  API did not change.

- **`AudioEmitter` where `SoundEmitter` was**, in
  `SoundEmitterComponent.emitter` and `AudioSceneComponent.play`: the same
  type under its 1.0 name, now that the old one is gone.

**Moves with the stack to 1.0.0**, whose `flutter3d_hardware` gives
`PassEncoder.draw` a window of the bound indices and every `PassEncoder`
`setAlphaToCoverage`.

Its `flutter3d_*` dependencies ask for `^1.0.0`.

## 0.8.4

**Heard from where the camera is this frame, wherever it was added.**
`AudioSceneComponent` works its mix out from the game's root through the
bridge's `UpdatesAtRoot`: added to the world it ran before Flame's camera,
whatever its priority, and the listener stood where the camera had been a
frame before. Needs `flame_flutter3d` 0.8.4, the release that has `UpdatesAtRoot`.

## 0.8.3

**Sound for a bridged Flame game, in a package of its own.**
`AudioSceneComponent` is the game's audio scene: silent until `open()`,
which belongs to the player's first key, touch or button because a browser
refuses a sound before one; heard from the game's 3D camera when it has
`HasFlutter3d`; mixed after everything else has moved. `play` makes a
one-shot, at a point in the scene or at the listener; `close` gives the
device back.

`SoundEmitterComponent` is a loop held open by state rather than started
and stopped by events: it plays while it is in the game and `playing` is
true, sounds from its bridged parent's place, follows `gain` and `rate`
every frame, and moves onto the speakers when they open. A loop a game
started on one event and meant to stop on another was left running when
the second never came.

Apart from `flame_flutter3d` because it brings SoLoud's native library, and
on the web its script, into whatever depends on it.

**A paused game is quiet.** `pause()` silences every sound where it is,
loops included, and `resume()` brings them back; a game sent to the
background is paused by itself. Flame stops updating a paused game, and an
engine loop went on droning under the pause menu at its last loudness.

**A refusal can be asked again, and a close wins.** An `open()` the browser
refused before the first touch stayed refused for the rest of the game; the
next one asks again. A `close()` made while the device was still opening
closes it as soon as it arrives instead of being overtaken by it.

**Emitters follow the game's sound.** A level restarted with a new
`AudioSceneComponent` left every emitter playing into the old one; they find
the new one. A one-shot emitter is not played a second time when the
speakers open, and a game with no sound is searched a few times a second
rather than every frame by every emitter.

**Heard the way the camera looks in the world.** The listener takes the 3D
camera's world turn rather than its turn against its parent: a camera
riding a craft was heard looking only its own way.
