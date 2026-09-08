## 0.6.0

* **Floors, and no code.** A run that can be started, saved, resumed and ended,
  still with no widget in it — byte for byte 0.5.0's. The floors on
  `flutter3d`, `flutter3d_game` and `flutter3d_screens`, and the dev floor on
  `flutter3d_cpu`, are `^0.6.0`.

## 0.5.0

* No API change. Released with the set.

## 0.4.1

* **A frame's cost, on request.** `FrameTimingLog` prints the mean and the
  worst of a frame's build and raster halves over every window of frames,
  when a build says `--dart-define=FLUTTER3D_TIMINGS=true`, and registers
  nothing otherwise. Two numbers rather than a frame rate, because a frame
  rate says a frame was late and not which half made it so.

## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* No changes of its own. The workspace is released as a set, in the order
  `ARCHITECTURE.md` §16 gives, so this package's version moves with the rest
  and its constraints on its siblings move with it.

## 0.2.0

* What a game is as an application: the surface a rendered frame reaches
  Flutter through, and the run being played — loading, resuming, moving on,
  failing.
* `FrameClock`, which answers how long since the last frame and says nought on
  the first one.
