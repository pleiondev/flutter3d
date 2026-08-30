# flutter3d example

Two ways in, smallest first.

**`lib/minimal_main.dart`** — one sphere, one point light, seventy lines:

```sh
flutter run -t lib/minimal_main.dart
```

It opens its device through `flutter3d_backend`, so the same file runs on
Impeller (desktop, mobile), WebGL2 (web) and the software rasteriser (anywhere
neither will start — including `flutter test`, which is how
`test/minimal_smoke_test.dart` runs it headless).

**`lib/main.dart`** — the engine's own demo: a model browser with every
lighting model, shadows, bloom, skinning, picking and the debug overlay. It is
also the harness `tool/golden.sh` drives to record the reference images, which
is why it stays the default target:

```sh
flutter run
```

The other entry points are instruments, not demos: `cpu_main.dart` runs the
same browser on the software backend, `conformance_main.dart` runs the backend
contract checks that cannot be a plain test, and `parity_main.dart` compares
backends against each other.
