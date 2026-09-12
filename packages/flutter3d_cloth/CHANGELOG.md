## 0.6.0

* **In the workspace at the set's number, and deliberately not on pub.dev.**
  A new package, written after 0.6.0's own set had already been decided —
  same reason `flutter3d_game_strategy` carries this number unpublished: a
  pubspec that names every workspace package names one tree, whether or not
  every named package has gone out yet.
* `ClothMesh.grid` and `stepCloth`: an XPBD cloth solver with distance and
  cross-edge bending constraints, pins via zero inverse mass, gravity, wind,
  damping and substeps, and collision against `flutter3d_physics`'s own
  `CollisionShape`.
