# flutter3d_app

The parts every Flutter application on flutter3d is assembled from, in one
import.

```dart
import 'package:flutter3d_app/flutter3d_app.dart';

final device = await openDevice(width: 1280, height: 720);
```

## What is in it

| | |
|---|---|
| `openDevice` / `presentFrame` | Which backend a build draws through, and the runtime fallback to the software rasteriser when Impeller will not start. |
| `Scene3D` and its children | A scene written as widgets: `Mesh3D`, `Model3D`, `Light3D`, `Camera3D`, `Node3D`, each owning one node of an ordinary `Scene`. A rebuild with the same keys keeps the nodes. |
| `SceneSurface` | The widget that hands a frame to Flutter. Its settings are a function called per frame, not an object, so anything derived from where the camera ended up is derived after it got there. |
| `WidgetSurface` | A live Flutter widget drawn onto a quad in the scene. |
| `LevelLoader` | A level document turned into mesh nodes, lights, probes and a collision world. Problems come back as `LoadedLevel.issues` rather than exceptions: a missing wall texture leaves the surface flat and says so. |
| `Storage` / `BinaryStorage` | A document kept where each platform keeps such things, behind one interface. |

## A scene as widgets

```dart
Scene3D(
  children: <Widget>[
    Camera3D(position: Vector3(2.0, 2.0, 4.0), target: Vector3.zero()),
    Light3D.directional(direction: Vector3(-1.0, -2.0, -1.5)),
    Mesh3D(
      key: const ValueKey<String>('crate'),
      shape: CuboidShape(),
      material: crate,
      position: Vector3(0.0, 0.5, 0.0),
    ),
    Model3D(
      source: 'assets_src/robot.glb',
      animation: 'Walk',
      placeholder: Mesh3D(shape: CuboidShape(), material: grey),
    ),
  ],
)
```

Each widget owns one node of an ordinary `Scene`, made once and given the
widget's properties on every build, so a widget that keeps its key keeps its
node and everything a game set on it. A property left null is left as the node
has it. `Scene3D.onCreated` hands over the device, the renderer and the scene
for whatever the widgets do not say; a game written against the imperative API
keeps it. A frame drawn from widgets is the frame the same scene draws when
built by hand, to the byte — `test/scene_widgets_test.dart` holds that.

## Universal, and that is the rule for what goes in

The modeller, the level editor, the lessons and every game use this package, so
nothing in it knows what a run, a binding or a monster is. Those belong to
[`flutter3d_game`](https://pub.dev/packages/flutter3d_game), which is built on this package. A name
only a game would want does not go here, however convenient one barrel would be.

`flutter3d`, `flutter3d_sim`, `flutter3d_game` and the genre packages are
deliberately left out of this barrel. Import them by name, so the choice shows
in the pubspec. [Assembling an application](https://flutter3d.pleion.dev/core/session/)
works through the full pattern, using `apps/flutter3d_demo_dungeon` as the
example.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an independent
implementation of a 3D engine for Flutter. It is not a fork or a binding of
another engine, and it is not affiliated with the Flutter team. It has four
switchable rendering backends: Impeller via Flutter GPU, WebGL2, WebGPU and a
software rasteriser. It loads glTF, OBJ and `.f3d`, and has six lighting models,
shadows, bloom, skinning, animation, BVH culling and picking, plus a
deterministic fixed-step game layer with collision, navigation, positional
audio, and gamepad and touch input. Four example games (shooter, platformer,
racing, strategy) are each built on a genre package:
[`flutter3d_game_shooter`](https://pub.dev/packages/flutter3d_game_shooter),
[`flutter3d_game_platformer`](https://pub.dev/packages/flutter3d_game_platformer),
[`flutter3d_game_racing`](https://pub.dev/packages/flutter3d_game_racing),
[`flutter3d_game_strategy`](https://pub.dev/packages/flutter3d_game_strategy).
A new game starts from the editor's scaffold, which writes one from a template:
<https://flutter3d.pleion.dev/first-project/>. Documentation:
<https://flutter3d.pleion.dev>.
