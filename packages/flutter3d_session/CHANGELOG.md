## 0.7.0

**Breaking.** Accepted `flutter3d_screens`, because this package already
depended on it for the one thing a run needs — `SaveFile` — and nothing
anywhere depended on `flutter3d_screens` without also depending on this
package (package-merge-plan.md §3.7). `SettingsOverlay`, `SaveFile`,
`SettingsFile`, `DemoFile`, `Storage`, rebinding, credits and the rest now
live under `src/screens/` and export through this package's own barrel and
its `native.dart`/`testing.dart` entry points; `flutter3d_screens` itself is
gone from the workspace. Nothing an application imports through
`flutter3d_app` changed; a caller that named `flutter3d_screens` directly
now names `flutter3d_session` instead.

**`SceneSurface` takes a new required `presentFrame` argument.**
`GraphicsDevice.present` is gone (mcp-01n), moved to `presentFrame` in
`flutter3d_app` — but that package depends on this one for `SceneSurface`
itself, so this package cannot depend back on it. `FramePresenter` names the
shape instead; every real caller already depends on both packages, so
passing `presentFrame: presentFrame` at the call site costs one line.

## 0.6.0

* **Floors, and no code.** A run that can be started, saved, resumed and ended,
  still with no widget in it — byte for byte 0.5.0's. The floors on
  `flutter3d`, `flutter3d_game` and `flutter3d_screens`, and the dev floor on
  `flutter3d_cpu`, are `^0.6.0`.
* **`WidgetSurface` (`wg-01`), without an accessibility tree.** A live widget
  as a mesh in the 3D scene — placement, UV-accurate pointer routing, a
  diagnostic redraw counter, and an isolated `FocusManager` a tap inside it
  can request focus on. **Semantics is deliberately not part of it**: a
  screen reader has no way to describe a control painted onto an arbitrary
  mesh in world space rather than laid out on the window, and building that
  tree is its own question, cut from this one rather than answered badly by
  it.

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
