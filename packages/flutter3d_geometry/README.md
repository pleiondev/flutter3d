# flutter3d_geometry

The geometry [flutter3d](https://flutter3d.pleion.dev) is written in, with no
Flutter SDK behind it: `VertexLayout` and `MeshData`, the shape generators a
scene is sketched from, tangents by Lengyel, morph targets and the texture they
are packed into, and the ray arithmetic that reads a triangle.

**Plain Dart.** `dart test` runs the suite with no binding, `dart compile exe`
builds a bench out of it, and a program that opens a mesh needs no window.

```dart
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:vector_math/vector_math.dart';

final cube = const CuboidShape(size: Vector3(1, 1, 1)).build();
print(cube.vertexCount); // 24 — a cube's corners, once per face normal

final hit = rayTriangle(
  Ray(Vector3(0, 0, 5), Vector3(0, 0, -1)),
  Vector3(-1, -1, 0),
  Vector3(1, -1, 0),
  Vector3(0, 1, 0),
);
```

## Why it is a separate package

Not tidiness. These twelve files sat in `packages/flutter3d/lib/src/engine` and
named Flutter nowhere at all — which was true and bought nobody anything, since
`flutter3d` declares `flutter: sdk` and a dependency on the engine brings the
SDK with it. Anything that wants to say `MeshData` without a window had to
either take the whole engine or copy the vocabulary, and a copied vocabulary is
two mesh formats a year later.

What wanted it is not hypothetical: a modeller's document layer, the tool an
agent starts with `dart run`, a service that checks an uploaded asset, and this
repository's own AOT benches.

## What it does not do

**It does not upload.** `DeviceMesh` and everything that has met a
`GraphicsDevice` stayed in `flutter3d`, which is the package allowed to name
one. The split is along that line and nowhere else: this package describes a
mesh, and the engine puts it on a card.

**It does not draw and it does not load.** A `Shape` builds `MeshData`; what
reads a `.glb` is `flutter3d_formats`, and what renders one is the engine.

The boundary is checked rather than described: `a flat Dart package resolves
without the Flutter SDK` in `tool/structure.dart` walks this package's
dependencies — direct and transitive — and fails on the first one that would put
a Flutter SDK back in front of a program that only wants to name a triangle.

`flutter3d` exports this package whole, so an application that already imports
the engine keeps every name it had.

## Licence

MIT.
