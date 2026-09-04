# flutter3d_bridge

The binding between `flutter3d` and `flutter3d_game`: level geometry to mesh
nodes, actors to visuals, fixtures to the lights they drive.

```dart
final loaded = await const LevelLoader().load(
  'assets/levels/first.json',
  device: device,
  registry: myKinds,
);
scene = loaded.scene;
```

**The one package allowed to know both halves.** The engine renders and knows
nothing about a level; the game layer holds levels and knows nothing about a
renderer. Something has to turn one into the other, and putting it in either
would give that package a dependency it exists not to have.

## Issues rather than exceptions

`LoadedLevel.issues` carries what did not work — a validator's warnings, a
texture that would not decode — because the application is the only thing here
with a screen. A missing wall texture leaves the surface flat and says so; it
does not stop the level.

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
