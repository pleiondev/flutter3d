# flutter3d_mesh

The mesh [flutter3d](https://flutter3d.pleion.dev)'s modeller edits, with the
topology still in it: faces of any valency, half-edges that know their twin, and
the operations that change them.

**Plain Dart.** No Flutter, no renderer, no disk.

```dart
import 'package:flutter3d_mesh/flutter3d_mesh.dart';

final cube = EditMesh.cuboid();
final step = cube.extrudeFace(0, 0.5);

print(step.eulerCharacteristic); // 2 — the surface is still closed
final drawable = step.toMeshData(); // what the engine draws
```

## Why it is not `MeshData`

`flutter3d_geometry` describes a mesh that is finished: vertices in the order a
GPU wants them, with a corner duplicated once per face normal that meets there.
Every question a modeller asks is about what that arrangement threw away — which
faces share this edge, what ring does this edge belong to, what is the loop
around this face. So editing needs the other representation, and drawing needs
this one converted.

## What is here today

The spike, and it says so in its own header: `EditMesh` builds from faces or as
a cuboid, walks loops without allocating, extrudes a face, validates its own
invariants, and converts to `MeshData`. Operations rebuild the arrays rather
than editing them in place — deliberately, because one of the answers the
measurements may give is that a rebuild per edit is affordable, and a spike that
assumed otherwise could not report it.

What comes next is in `doc/model-editor-plan.md`: persistent chunked arrays,
attribute layers, selections, loop cuts, dissolves, modifiers.

## Licence

MIT.
