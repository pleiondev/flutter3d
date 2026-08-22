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
