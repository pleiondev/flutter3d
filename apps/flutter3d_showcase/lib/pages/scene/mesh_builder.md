# Building a mesh in code

A shape generator is a `MeshBuilder` used the same way a hand-written mesh
would be. This page skips the generator and writes the pyramid by hand, one
vertex and one triangle at a time.

## Step 1: Start from a layout

`MeshBuilder` is handed the layout it should write. `VertexLayout.standard` is
what the lit shaders read: position, normal, texture coordinates, tangent and
colour. An attribute the layout does not declare is simply ignored if it is
passed in.

{{code builder}}

## Step 2: Add vertices and triangles

`addVertex` returns the index it was stored at, which is exactly what
`addTriangle` and `addQuad` need. The four side faces share the apex and each
computes its own flat normal from the two edges that meet there, so the
pyramid reads as faceted rather than smoothed.

{{code faces}}

## Step 3: Draw it

The finished `MeshData` uploads and draws exactly like one that came from a
shape.

{{code scene}}

## Step 4: Check the counts

Five vertices went in: one apex and four base corners, none of them repeated.
Eighteen indices came out: four side triangles and a base split into two.

{{code check}}
