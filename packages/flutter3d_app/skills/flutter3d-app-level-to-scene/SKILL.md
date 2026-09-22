---
name: flutter3d-app-level-to-scene
description: Use when turning a flutter3d level into something drawable — LevelLoader, the scene and collision world it produces, and why problems come back as issues.
---

# A level document, loaded into a scene

The engine renders and knows nothing about a level; `flutter3d_sim` holds levels
and knows nothing about a renderer. The conversion lives in `flutter3d_app`,
which every application stands on: a game plays a level with it, and the editor
and the lessons draw one with the same code.

```dart
final loaded = await const LevelLoader().load(
  'assets/levels/first.json',
  device: device,
  registry: myKinds,       // the game's own EntityKind vocabulary
);

scene = loaded.scene;              // MeshNodes, lights, probes
collision = loaded.collision;      // a CollisionWorld built from the brushes
for (final issue in loaded.issues) show(issue);
```

`LoadedLevel` also carries `level`, `brushNodes`, `materialTextures`,
`drawCallCount` and the visibility culler when the level shipped one.
`build(level, …)` is the same work over a `Level` already in hand, which is what
an editor and a test use.

## Issues rather than exceptions

`issues` carries what did not work: a validator's warning, a texture that would
not decode, a sidecar that was not there. The application is the only thing here
with a screen, so it decides what to show — a missing wall texture leaves the
surface flat and says so, and does not stop the level.

An empty `issues` list is the assertion worth writing in a test. A level that
loads and looks wrong nearly always explained itself there and nobody looked.

## Sidecars

Visibility and lightmap sidecars load beside the level and turn off with
`sidecars: false`. Asking for them when a game has none is two guaranteed 404s
in the console of every web build; shipping the tables anyway is megabytes per
game that culls nothing. Decide once per game, at the call site.

## The rest

`SharedMeshes` keeps one mesh per shape instead of one per instance, and
`VisibilityCuller` applies the level's own data. What a game's simulation moves
is drawn by `flutter3d_game`: `ActorVisuals` binds actors to the nodes
representing them, `FixtureVisuals` binds fixtures to the lights they drive, and
`SoundOcclusion` makes a wall between the player and a source audible.

All of them take the scene and the level as values. Nothing here holds a running
game, which is why an editor can draw a level it is in the middle of editing.
