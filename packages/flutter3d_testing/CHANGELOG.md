## 0.6.0

* **Floors, and no code.** Drawing a frame through the software backend and
  holding it to a reference image works exactly as it did in 0.5.2. The floors
  on `flutter3d`, `flutter3d_cpu` and `flutter3d_hardware` are `^0.6.0` — and
  they matter more here than in most places, because a golden helper resolved
  against a different engine than the game under test compares two different
  renderers and calls the difference a regression.

## 0.5.2

* `^0.5.2` on both halves. This package is the one place the engine and the
  software backend are named together, so it is where "these two move as a
  pair" can be written at all — see `flutter3d_backend` 0.5.2 for what a
  mismatched pair does with morph targets.

## 0.5.1

* **Its floors move to `flutter3d` and `flutter3d_cpu` at 0.5.1, both of
  them.** This package pairs the engine with the software backend, and 0.5.1
  changed a contract they share: what the surface buffer's alpha holds, and the
  members of the `FogInfo` block. Either half at 0.5.0 against the other at
  0.5.1 draws a picture that is quietly the old one — the software backend
  reads a missing uniform member as zeros rather than refusing, so nothing says
  anything. Naming both floors is what closes it in both directions, which
  `flutter3d_backend` cannot do because it does not depend on the engine.

## 0.5.0

**Breaking.** The frame builder takes one object.

* **`FrameBuilder` is `FrameSubject Function(FrameRequest)`**, so telling a
  builder the size it is drawing at, or which backend it is on, does not break
  every builder anybody has written.

## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* First release. `renderFrame` draws a scene through the software backend, with
  no GPU, no driver and no display; `expectMatchesGolden` holds the result to a
  reference image, recording one when there is none.
* The tolerance defaults to zero, because a software rasteriser draws the same
  scene the same way twice and a test that allows drift has stopped watching
  it.
