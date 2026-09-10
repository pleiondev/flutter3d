---
name: flutter3d-mesh-editing-topology
description: Use when editing mesh topology with flutter3d_mesh — half-edges and n-gons, selections, the operations, undo, and conversion to and from drawable MeshData.
---

# A mesh with the topology still in it

```dart
final cube = EditMesh.cuboid();
final step = cube.extrudeFace(0, 0.5);

step.eulerCharacteristic;    // 2 — the surface is still closed
final drawable = step.toMeshData();
```

Plain Dart: no Flutter, no renderer, no disk.

`flutter3d_geometry` describes a mesh that is finished — vertices in the order a
GPU wants them, a corner duplicated once per face normal that meets there. Every
question a modeller asks is about what that threw away: which faces share this
edge, what ring it belongs to, what the loop around this face is. Edit here,
convert to draw.

## Journalled, and never renumbered

An edit is recorded and `undo` takes it back; a deleted element is a tombstone
rather than a renumbering, so indices a caller kept stay valid across an edit.
That is what lets a selection outlive an operation.

Attribute layers — UVs and colours per corner, skin weights per vertex,
sharpness and creases per edge, material slot and smoothing per face — cost
nothing until something writes to them.

`Selection` is sorted numbers at one level and never a flag on the mesh, so
undoing a move does not undo the click that set it up. It converts between
vertices, edges and faces, grows and shrinks, walks loops and rings, follows an
island and reports the border of a region.

## Every operation has the same shape

A mesh, a selection, parameters, and an `OpResult` that says what changed and
what to redraw — or refuses in a sentence somebody can act on. Pass the refusal
through to the user; it is written to be read.

- move: `translateSelection`, `rotateSelection`, `scaleSelection`;
- build: `extrudeFaces`, `extrudeEdges`, `loopCut`, and `splitEdge` /
  `splitFace` underneath;
- take apart: `deleteSelection`, `duplicateSelection`, `splitSelection`,
  `separateComponents`;
- simplify: `dissolveEdge`, `dissolveVertex` — the faces around merge rather
  than leaving a hole, so dissolving the diagonals of a triangulated box gives
  back its six quads;
- weld: `mergeByDistance`, `mergeAt` rebuild rather than rewire, and report what
  it cost: faces that stopped being polygons, walls between two solids that are
  now one, edges that came out with a third face.

## Drawing, picking and checking

`MeshLayoutPlan` computes triangles, corner normals and which corners are one
GPU vertex once, then refills only the rows of vertices somebody moved.
`MeshNormals` breaks fans at a sharp edge, an unsmoothed face, or an angle wider
than the caller allows.

`MeshBvh` answers in faces — `refit` while somebody drags, `rebuild` when the
topology changes. `MeshPicker` turns where they pointed into what they meant:
the face a ray hits, the nearest vertex or edge to the line, everything inside a
rectangle.

`MeshChecks` **names the elements rather than counting them**, so a viewport can
turn an issue into a selection: n-gons, rims, vertices where two surfaces meet
at a point, vertices nothing stands on, faces with no area, coincident vertices,
shells wound inside out, and the Euler characteristic of each island.

## Coming in and going out

`importMeshData` welds duplicated corners, turns mirrored faces round and
detaches a third face on an edge, and **reports each** rather than doing it
quietly.

The parametric primitives (`ParametricCuboid`, `ParametricPlane`,
`ParametricCylinder`, `ParametricSphere`, `ParametricTorus`, `ParametricLathe`)
are the engine's shapes built the other way: quads, one vertex per corner, sharp
rings where the engine repeats a profile point, a flat cap as one n-gon. Each
carries the engine's `Shape` beside it, held to the same volume, bounds and
texture coordinates.

`toBytes` / `fromBytes` are the mesh as a file: tagged sections on four-byte
boundaries, little-endian, deterministic, and an unknown section is stepped over
rather than fatal. `editInIsolate` sends a mesh across as those bytes inside a
`TransferableTypedData`, with the work as a named function rather than a
closure; with no isolates it does the work where it stands and says so.
