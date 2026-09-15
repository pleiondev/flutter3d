# flutter3d_app

What any Flutter application on flutter3d is assembled from, as one import.

```dart
import 'package:flutter3d_app/flutter3d_app.dart';

final device = await openDevice(width: 1280, height: 720);
```

## What is in it

| | |
|---|---|
| `openDevice` / `presentFrame` | Which backend a build draws through, and the runtime fallback to the software rasteriser when Impeller will not start. |
| `SceneSurface` | The widget that hands a frame to Flutter. Its settings are a **function called per frame**, not an object, so anything derived from where the camera ended up is derived after it got there. |
| `WidgetSurface` | A live Flutter widget drawn onto a quad in the scene. |
| `LevelLoader` | A level document turned into mesh nodes, lights, probes and a collision world. Problems come back as `LoadedLevel.issues` rather than exceptions: a missing wall texture leaves the surface flat and says so. |
| `Storage` / `BinaryStorage` | A document kept where each platform keeps such things, behind one interface. |

## Universal, and that is the rule for what goes in

The modeller, the level editor, the lessons and every game use this package.
Nothing in it knows what a run, a binding or a monster is: that is
[`flutter3d_game`](../flutter3d_game), which stands on this package. A name only
a game would want does not belong here, however convenient one barrel would be.

What is deliberately not behind it: `flutter3d`, `flutter3d_sim`,
`flutter3d_game` and a genre package. Import them by name, so the choice is
visible in the pubspec. See
[Assembling an application](https://flutter3d.pleion.dev/core/session/) for the
full pattern, worked through with `apps/flutter3d_demo_dungeon` as the example.

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
