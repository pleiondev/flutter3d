# flutter3d example

There are two entry points here, the one to start from first.

**`lib/minimal_main.dart`** is one sphere and one point light in one
`Flutter3dView`:

```sh
flutter run -t lib/minimal_main.dart
```

The view opens its device through `flutter3d_app`, so the same file runs on
Impeller (desktop, mobile), WebGL2 (web) and the software rasteriser (anywhere
neither of those starts, including `flutter test`; that is how
`test/minimal_smoke_test.dart` runs it headless). A web build of it tries
WebGPU first and falls back to WebGL2; `--dart-define=FLUTTER3D_WEBGPU=false`
keeps WebGL2 only and leaves the WebGPU backend out of the bundle.

The other packages' examples start from `Flutter3dView` too: a digital twin
fed by a real source in `flutter3d_app/example/lib/twin_main.dart`, a
pendulum laboratory on the accurate profile in
`flutter3d_education/example/lib/pendulum_main.dart`, and the seed of a game
in `flutter3d_game/example`.

**`lib/main.dart`** is the engine's own demo: a model browser with every
lighting model, shadows, bloom, skinning, picking and the debug overlay. It is
also the harness `tool/golden.sh` drives to record the reference images, which
is why it stays the default target and is built a layer lower, on
`SceneSurface`:

```sh
flutter run
```

The other entry points are measuring tools. `cpu_main.dart` runs the same
browser on the software backend, `conformance_main.dart` runs the backend
contract checks that cannot be a plain test, `surface_probe_main.dart` measures
flutter_gpu's `GpuImageSurface` against the path `present` uses, and
`parity_main.dart` compares backends against each other.
