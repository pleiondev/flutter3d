## Unreleased

**Heard from where the camera is this frame, wherever it was added.**
`AudioSceneComponent` works its mix out from the game's root through the
bridge's `UpdatesAtRoot`: added to the world it ran before Flame's camera,
whatever its priority, and the listener stood where the camera had been a
frame before. Needs the `flame_flutter3d` release that has `UpdatesAtRoot`.

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
