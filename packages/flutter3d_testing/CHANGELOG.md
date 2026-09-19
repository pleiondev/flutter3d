## 0.7.0

* **Breaking for code that builds a `RenderedFrame` by hand.** The record
  gained a fourth field, `drawCalls`, read off the `FrameResult` every render
  already produced. `renderFrame` fills it, and a test can now assert how many
  draws a scene cost as well as what it looked like. Code that only reads
  `pixels`, `width` and `height` is unaffected; a literal
  `(pixels:, width:, height:)` passed where a `RenderedFrame` is wanted no
  longer has the type.
* **`replayGolden`: a recorded run, replayed to one step, held to a picture.**
  It drives an `InputState` from a `Demo`'s tape, calls the caller's `onStep`
  once per entry, draws the caller's `frame` at `atStep` through `renderFrame`
  and compares with `expectMatchesGolden`. A `DigestTrace` already says
  whether a replay reached the same numbers; this is for a renderer that
  changed under numbers that did not. The step is the caller's because a
  genre's simulation is not this package's to know. A tape that ends before
  `atStep` throws `StateError`, so a short recording is not reported as a
  wrong picture. `flutter3d_sim` `^0.7.0` is a dependency for it.
* **`MaterialProgramStage` draws a material written as source on the software
  backend.** It implements `flutter3d_cpu`'s `CpuFragmentShader` over a
  `MaterialProgram` from `package:flutter3d_core/formats.dart` that has been
  through `specialiseMaterial`, and evaluates the same tree the GLSL emitter
  writes from. It lives here because `flutter3d_cpu`'s
  `lib/` may not reach the engine and the engine may not reach a backend.
  `flutter3d_core` `^0.7.0` is a dependency for it.
* The archive carries a skill for a coding agent,
  `skills/flutter3d-testing-pixel-regression/`, which a project depending on
  this package installs with `dart run skills@ get`.
* The floors on `flutter3d`, `flutter3d_cpu` and `flutter3d_hardware` are
  `^0.7.0`. `renderFrame`, `expectMatchesGolden` and the tolerance of zero are
  unchanged.

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
