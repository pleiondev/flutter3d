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

`EditMesh` holds the topology in nine journalled arrays, so an edit is recorded
and `undo` takes it back, and a deleted element is a tombstone rather than a
renumbering. Over that sit the attribute layers — UVs and colours per corner,
skin weights per vertex, sharpness and creases per edge, material slot and
smoothing per face — each of which costs nothing until something writes to it.

`importMeshData` rebuilds an editable mesh from a drawable one, welding
duplicated corners, turning mirrored faces round and detaching the third face on
an edge, and it reports each of those. Going the other way, `MeshLayoutPlan`
works out the triangles, the corner normals and which corners are one GPU vertex
— once — and then refills only the rows of the vertices somebody moved.
`MeshNormals` is the shading underneath that: fans broken by a sharp edge, by a
face nobody smoothed, or by an angle wider than the caller allows.

`Selection` is what a person has picked — sorted numbers at one level, never a
flag on the mesh, so undoing a move does not undo the click that set it up. It
converts between vertices, edges and faces, grows and shrinks, walks edge loops
and rings, follows an island and reports the border of a region.

Two edits are here so far. `dissolveEdge` and `dissolveVertex` take an edge or a
vertex out and leave the faces around it merged rather than a hole — dissolving
the diagonals of a triangulated box gives back the six quads it was — and each
is one step of history. `mergeByDistance` and `mergeAt` weld vertices together,
rebuilding rather than rewiring, and report what that cost: faces that stopped
being polygons, walls between two solids that have become one, edges that came
out with a third face on them.

What comes next is in `doc/model-editor-plan.md`: selections, loop cuts,
dissolves, modifiers, and the operations that edit in place rather than
rebuilding.

## Licence

MIT.
