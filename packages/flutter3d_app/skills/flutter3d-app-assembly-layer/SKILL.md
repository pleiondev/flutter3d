---
name: flutter3d-app-assembly-layer
description: Use when starting or wiring a flutter3d application — this one import is the assembly layer, and a game still names the engine and its genre for itself.
---

# One import for the wiring, and no code of its own

```dart
import 'package:flutter3d_app/flutter3d_app.dart';

final device = await openDevice(width: 1280, height: 720);
```

Five `export` lines over the packages an application needs beyond the renderer
and the simulation:

| Behind the facade | What it gives |
|---|---|
| `flutter3d_backend` | `openDevice`, `kFixedResolution` |
| `flutter3d_session` | `SceneSurface`, `RunSession`, the frame clock |
| `flutter3d_screens` | settings, volumes, rebinding, credits, saves |
| `pad_input` | a gamepad, as a snapshot the caller asks for |
| `pointer_lock` | desktop mouse capture, which Flutter offers nowhere |

None of the five know about each other, and this does not change that.

## What is deliberately not behind it

`flutter3d`, `flutter3d_bridge`, `flutter3d_game` and a genre package. Those are
content — what a scene looks like and what kind of game this is — and a facade
cannot pick a genre on an application's behalf. Import them by name, so the
choice is visible in the pubspec.

## The shape of a main file

Open the device, build the renderer, build the game's own assembly (the one
function that turns a level into a run — see
`flutter3d-session-one-assembly`), mount a `SceneSurface`, put the screens over
it. Worked through with `apps/flutter3d_demo_dungeon` at
<https://flutter3d.pleion.dev/core/session/>.

Two things belong to the application alone: enabling Flutter GPU and Impeller in
its own platform manifests, and deciding the render resolution and shadow budget
for its own scene.
