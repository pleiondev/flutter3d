# flutter3d_app

The layer an application is assembled from, as one import.

```dart
import 'package:flutter3d_app/flutter3d_app.dart';

final device = await openDevice(width: 1280, height: 720);
```

## Why it is a package

Five packages hold the wiring a game needs beyond the renderer and the
simulation: `flutter3d_backend` (which device to open), `flutter3d_session`
(`SceneSurface`, `RunSession`), `flutter3d_screens` (settings, rebinding, saves),
`pad_input` (a gamepad), `pointer_lock` (desktop mouse capture). None of the
five know about each other, and this package does not change that — it holds
no code of its own, only five `export` lines.

What it buys is that an application's own `pubspec.yaml` and `main.dart` say
"the assembly layer" once, the way importing `flutter3d` already says "the
renderer" once instead of naming `flutter3d_hardware` directly.

## What is deliberately not behind it

`flutter3d`, `flutter3d_bridge`, `flutter3d_game`, and a genre package.
Those are content — what a scene looks like and what kind of game this is —
and a facade cannot pick a genre on an application's behalf. See
[Assembling an application](https://flutter3d.pleion.dev/core/session/) for
the full pattern, worked through with `apps/flutter3d_demo_dungeon` as the example.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an **independent
implementation** of a 3D engine for Flutter — not a fork or a binding of
another engine, and not affiliated with the Flutter team. Three switchable
rendering backends: Impeller via Flutter GPU, WebGL2, and a software
rasteriser. glTF, OBJ and `.f3d` loading, six lighting models, shadows, bloom,
skinning, animation, BVH culling and picking; a deterministic fixed-step game
layer with collision, navigation, positional audio, and gamepad and touch
input. Three example games — shooter, platformer, racing — each built on its
genre package: [`flutter3d_game_shooter`](../flutter3d_game_shooter),
[`flutter3d_game_platformer`](../flutter3d_game_platformer),
[`flutter3d_game_racing`](../flutter3d_game_racing). A new game starts from the
editor's scaffold, which writes one from a template: <https://flutter3d.pleion.dev/first-project/>.
Documentation: <https://flutter3d.pleion.dev>.
