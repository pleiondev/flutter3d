## 0.6.0

**The first release. It takes the set's number rather than a first number of its
own**, because the whole workspace goes out together and geometry resolved
against a different `flutter3d` than the renderer above it would describe a mesh
the engine does not draw. What follows is what this package is, not what changed
in it: the files came out of `flutter3d` unaltered.

* **The geometry the engine is written in, with no Flutter SDK behind it.**
  `VertexLayout`, `MeshData`, `MeshBuilder`, `Shape` and the generators over it
  — cuboid, plane, sphere, cylinder, torus and `LatheShape` — `MeshGeometry` and
  `CpuMesh`, tangents by Lengyel, morph targets, `MorphTexture`, `morph_blend`,
  and `Ray` with the intersection arithmetic that reads one.

* **The reason it moved is that `flutter3d` declares `flutter: sdk`.** Every
  file here named Flutter nowhere, and it made no difference: a package that
  depended on the engine to say `MeshData` resolved a Flutter SDK it had no use
  for, and `dart pub get` in a container without one failed. A modeller's
  document layer, a tool an agent starts with `dart run` and this repository's
  own AOT benches all wanted the vocabulary and none of them wanted a widget.

* **`DeviceMesh` stayed in `flutter3d`,** with the two types that have met a
  `GraphicsDevice`. That is the line the split was made along, and the only one:
  this package describes a mesh, the engine uploads it.

* **`flutter3d` exports this package whole,** so an application that imports the
  engine keeps every name it had and the move is invisible to it.
