## Unreleased

**Breaking.** What any application needs from `flutter3d_session` and
`flutter3d_bridge` is here now, and nothing is re-exported.

* From `flutter3d_session`: `SceneSurface`, `FrameClock`, `FrameTimingLog`,
  `DidNotStart`, the status screens, `WidgetSurface` and its pipeline, and
  `Storage`/`BinaryStorage`, with the atomic write in `native.dart`.
* From `flutter3d_bridge`: `LevelLoader`, `LoadedLevel`, `SharedMeshes`,
  `SurfaceMesh`, `VisibilityCuller` and `WidgetSurfaceVisuals`.
* From `flutter3d_game`: `Issue`, `IssueSink` and `IssueLog`, which a storage
  reports through.
* No longer re-exported: `flutter3d_session`, `pad_input` and `pointer_lock`.
  What a game took from the first is `flutter3d_game` now, and a game names the
  two device packages itself.

## 0.7.0

**Breaking.** Accepted `flutter3d_backend`, because most of its consumers
already reached it through this barrel rather than by naming it, and the
handful that still named it directly — two package examples, and one game's
now-redundant line — cost nothing to repoint, which left the separate
package with no boundary of its own (package-merge-plan.md §3.6). The
conditional export deciding which backend a
build draws through — `openDevice`, `kFixedResolution` — now lives directly
in this package's own `src/backend_native.dart`/`src/backend_web.dart`, and
this package depends directly on `flutter3d_hardware`, `flutter3d_impeller`,
`flutter3d_webgl`, `flutter3d_cpu` and `flutter3d_webgpu` instead of on
`flutter3d_backend`. Nothing an application imports changed.

**`presentFrame(device, frame, {fit, quality})`, new — a registry lookup, not
a fixed list.** `GraphicsDevice.present` is gone (mcp-01n), and what replaces
it is `flutter3d_hardware`'s own device registry: `registerBackendOpener` and
`registerDevicePresenter`, which every backend — including a third-party one
this repository has never heard of — calls on itself. `flutter3d_impeller`
and `flutter3d_webgl` register both halves from their own packages;
`flutter3d_cpu` registers only its opener, since the flat package that went
through mcp-02n cannot also build a Flutter `Widget` for `CpuFrame`, which
moved here. This package's `openDevice`/`presentFrame` are the batteries-
included default: they make sure the four backends this repository ships
have registered themselves, then hand the question to the registry — a
caller who wants a fifth backend, or none of these four, can register
directly with `flutter3d_hardware` and never name this package at all.

**`SceneSurface` in `flutter3d_session` now takes a `presentFrame`-shaped
callback** as a required constructor argument rather than naming this
package — the dependency runs the other way — so every existing
`SceneSurface` call site needs one line added: `presentFrame: presentFrame`.

## 0.6.0

* **Floors, and no code.** Storage, settings, the frame clock and the screens
  are byte for byte 0.5.0's. `flutter3d_backend`, `flutter3d_session` and
  `flutter3d_screens` move to `^0.6.0`; `pad_input` and `pointer_lock` stay at
  `^0.4.0`, which their 0.4.1 covers.
* **What arrives through the barrel is one line wider without this package
  changing.** `flutter3d_backend` 0.6.0 can try WebGPU on a web build given
  `--dart-define=FLUTTER3D_WEBGPU=true`; an application assembled from here
  gets that by raising the floor and nothing else, because `openDevice` was
  always the whole of the question this layer asks.

## 0.5.0

* No API change. Its floors move to the 0.5.0 packages it assembles.

## 0.4.0

* No changes of its own; the version moves with the workspace, whose sibling
  constraints name a single release. The README's closing section now says
  what the engine around this package is.

## 0.3.0

* A barrel over `flutter3d_backend`, `flutter3d_session`, `flutter3d_screens`,
  `pad_input` and `pointer_lock` — the five packages an application assembles
  itself from, none of which know about each other. No code of its own.
