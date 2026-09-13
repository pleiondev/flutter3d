# flutter3d_render_job

A model project rendered off its own device — `pro-rn-02`'s own row: a
snapshot drawn by the same renderer, the same frame-graph passes and the
same tiling the live viewport uses, on a `CpuDevice` of its own so it never
contends with whatever the viewport is actually drawing with.

```dart
final job = RenderSnapshotJob(project, RenderPreset(
  width: 480,
  height: 360,
  camera: SnapshotCamera(
    position: Vector3(2.2, 1.4, 3.4),
    target: Vector3.zero(),
  ),
));
final png = await job.run();
```

## What a `RenderPreset` states

`ModelProject` carries no camera of its own, so [`SnapshotCamera`] states
one. `ssaa` is 1 or 2 — 2 renders a linear 2×2 supersample and resolves it
back down with a box filter, the resolve `packages/flutter3d_cpu`'s own
`pro-rn-01` benchmark named as missing when it measured a bigger render
target as an honest proxy for supersampling's *cost* rather than its
picture. `tilesX`/`tilesY` render the frame as a grid of
[`TiledProjection`] tiles and stitch them back — `(1, 1)`, the default, is
one tile the size of the whole frame.

## Native and web

`run()` decides for itself: the whole grid renders inside one
`Isolate.run` on native (`flutter3d_mesh`'s own `meshWorkStaysHere` says
which), or one tile per chunk with a yield between them on the web, where
`Isolate.run` is a stub. A caller that wants its own progress bar and
cancel button can skip `run()` and drive `chunkCount`/`renderTile`/`finish`
directly instead — the same shape `apps/flutter3d_modeler`'s own `Job<T>`
already asks any job for, without this package depending on the
application that class lives in.

## What it does not do yet

No textures — a snapshot renders a project's base colour, metallic and
roughness alone, the same "clay" the live viewport itself shows for one
frame while its own material pool is still decoding. No parent hierarchy —
every object draws in its own local transform, not nested under
`ModelObject.parent`. Both are real gaps, not silent ones; see
`scene_from_project.dart`'s own doc comment for why each is out of this
row's own scope.
