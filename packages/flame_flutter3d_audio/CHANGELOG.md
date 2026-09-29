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
