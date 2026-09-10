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

Every edit has the same shape — a mesh, a selection, its parameters, and an
`OpResult` that says what changed and what to redraw, or refuses in a sentence
somebody can act on. `translateSelection`, `rotateSelection` and
`scaleSelection` move what is selected and nothing else; `extrudeFaces` and
`extrudeEdges` detach a region, wall in the gap behind it and lift it; `loopCut`
runs a new loop of edges across a ring of quads, out of `splitEdge` and
`splitFace`, which are worth having on their own. `deleteSelection`,
`duplicateSelection`, `splitSelection` and `separateComponents` take a mesh
apart and put copies of pieces back.

`ParametricCuboid`, `ParametricPlane`, `ParametricCylinder`,
`ParametricSphere`, `ParametricTorus` and `ParametricLathe` are the engine's
own primitives built the other way: quads, one vertex per corner, sharp rings
where the engine repeats a profile point, and a flat cap as one n-gon rather
than a fan. Each carries the engine's `Shape` beside it, and the two are held
to the same volume, bounds and texture coordinates.

`MeshBvh` puts a tree over the plan's triangles and answers in faces —
`refit` while somebody drags, `rebuild` when the topology changes — and
`MeshPicker` turns where they pointed into what they meant: the face a ray
hits, the nearest vertex or edge to the line they pointed along, everything
inside a rectangle.

`toBytes` and `fromBytes` are the mesh as a file: tagged sections on
four-byte boundaries, little-endian, deterministic, and a section a reader does
not know is stepped over rather than fatal.

`editInIsolate` takes a mesh somewhere else and brings it back: it crosses as
the bytes above, inside a `TransferableTypedData`, and the work is a named
function rather than a closure. On a build with no isolates it does the work
where it stands and says so.

`editInIsolate` takes a mesh somewhere else and brings it back: it crosses as
those bytes, inside a `TransferableTypedData`, and the work is a named function
rather than a closure. On a build with no isolates it does the work where it
stands and says so.

`MeshChecks` says what is wrong with a mesh and names the elements rather than
counting them, so a viewport turns an issue into a selection: n-gons, rims,
vertices where two surfaces meet at a point, vertices nothing stands on, faces
with no area, vertices standing on top of each other, shells wound inside out,
and the Euler characteristic of each island.

`dissolveEdge` and `dissolveVertex` take an edge or a
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
