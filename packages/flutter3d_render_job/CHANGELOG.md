## 0.1.0

* **A new package, written after 0.6.0's own set had already been decided** —
  same reason `flutter3d_stereo` carries its own version track rather than
  the workspace's shared one: nothing in the workspace depends on this
  package yet, so nothing pins a version to it.
* `RenderSnapshotJob`/`RenderPreset`/`SnapshotCamera`: a model project
  rendered off its own `CpuDevice` — the same renderer, the same frame-graph
  passes and the same `TiledProjection` tiling the live viewport draws
  with — SSAA ×1/×2 resolved with a box filter, PNG-encoded through
  `flutter3d_model_core`'s own encoder, an isolate on native and one tile
  per chunk everywhere else.
