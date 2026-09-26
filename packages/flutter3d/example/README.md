# flutter3d example

There are two entry points to start from, the smaller one first.

**`lib/minimal_main.dart`** is one sphere and one point light in seventy lines:

```sh
flutter run -t lib/minimal_main.dart
```

It opens its device through `flutter3d_app`, so the same file runs on
Impeller (desktop, mobile), WebGL2 (web) and the software rasteriser (anywhere
neither of those starts, including `flutter test`; that is how
`test/minimal_smoke_test.dart` runs it headless). Given
`--dart-define=FLUTTER3D_WEBGPU=true`, a web build of it tries WebGPU first;
the `flutter3d_app` README explains that option and what it costs.

**`lib/main.dart`** is the engine's own demo: a model browser with every
lighting model, shadows, bloom, skinning, picking and the debug overlay. It is
also the harness `tool/golden.sh` drives to record the reference images, which
is why it stays the default target:

```sh
flutter run
```

The other entry points are measuring tools. `cpu_main.dart` runs the same
browser on the software backend, `conformance_main.dart` runs the backend
contract checks that cannot be a plain test, `surface_probe_main.dart` measures
flutter_gpu's `GpuImageSurface` against the path `present` uses, and
`parity_main.dart` compares backends against each other.
