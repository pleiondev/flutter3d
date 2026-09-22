---
name: flutter3d-app-assembly-layer
description: Use when starting or wiring a flutter3d application — this one import picks the GraphicsDevice and holds the surface, storage and level loading every application shares; a game adds flutter3d_game on top.
---

# One import for what every application shares

```dart
import 'package:flutter3d_app/flutter3d_app.dart';

final device = await openDevice(width: 1280, height: 720);
final renderer = Renderer.create(device: device);
```

| What | Where to start |
|---|---|
| the backend choice | `openDevice`, `presentFrame`, `kFixedResolution` |
| the surface | `SceneSurface`, `FrameClock`, `FrameTimingLog`, `DidNotStart`, the status screens |
| widgets in the scene | `WidgetSurface`, `WidgetSurfaceVisuals` |
| a level in a scene | `LevelLoader`, `SharedMeshes`, `VisibilityCuller` — see `flutter3d-app-level-to-scene` |
| storage | `Storage`, `BinaryStorage`, and `Issue` for a document that cannot be read |

The modeller, the level editor and the lessons use this and nothing above it. A
game adds `flutter3d_game`: the input devices, the run, the settings screens,
and the actors and fixtures drawn.

## The backend choice, and the two run-time fallbacks

On a desktop or phone the device is `flutter3d_impeller`'s; in a browser it is
`flutter3d_webgl`'s. **Web against native is a conditional export, not an
`if`**: `flutter_gpu` does not compile for the web and `dart:js_interop` does
not compile for macOS, so a file importing both targets nothing. Call
`openDevice`; do not write such a file.

The software rasteriser is where a native build lands when Impeller will not
start, so a machine with no working GPU still draws. WebGPU is asked for only
when a build asks:

```sh
flutter build web --dart-define=FLUTTER3D_WEBGPU=true
```

and falls back to WebGL2 where the browser has no `navigator.gpu` or hands out
no adapter. Off by default because of size: the probe has to call both
openers, so a build carrying it carries both backends — 376,649 bytes of
`main.dart.js` on the strategy demo, 14.9% more script. An ordinary web build
draws through WebGL2, which is the browser backend with a recorded reference
set behind it.

`kFixedResolution` says whether the backend renders into a fixed internal
target — true in a browser, where a WebGL canvas resets its drawing buffer on
resize — and what that size should be is the game's own trade:

```dart
final size = kFixedResolution ? const Size(960, 540) : screenSize;
```

## What is deliberately not behind it

`flutter3d`, `flutter3d_sim`, `flutter3d_game` and a genre package. Import them
by name, so the choice is visible in the pubspec. Nothing from another package
is re-exported either: `pad_input` and `pointer_lock` are a game's devices, and
the game names them.

## The shape of a main file

Open the device, build the renderer, build the game's own assembly (the one
function that turns a level into a run — see `flutter3d-game-one-assembly`),
mount a `SceneSurface`, put the screens over it. Worked through with
`apps/flutter3d_demo_dungeon` at <https://flutter3d.pleion.dev/core/session/>.

Two things belong to the application alone: enabling Flutter GPU and Impeller in
its own platform manifests, and deciding the render resolution and shadow budget
for its own scene.
