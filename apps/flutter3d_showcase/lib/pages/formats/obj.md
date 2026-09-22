# OBJ and MTL

Wavefront OBJ is plain text, older than glTF, and still what a lot of
tools export by default. This page reads a tiny hand-written OBJ, fills
in what it left out, and writes it back.

## Step 1: A file with no normals

Real OBJ files skip `vn` often enough that a loader has to have an answer
for it. This tetrahedron has four vertices and four faces, and nothing
else.

{{code source}}

## Step 2: Decode it, and let the loader fill the gap

`ObjNormals.smooth`, the default, averages the face normals meeting at
each vertex rather than leaving them at zero. A flat-shaded look on a
curved surface is exactly what leaving normals at zero would produce.

{{code load}}

> **Note.** `ObjNormals.flat` gives one normal per face instead, which
> needs shared vertices split apart first. `ObjNormals.none` leaves them
> at zero, for a caller that computes its own.

## Step 3: Write it back out

`ObjWriter` takes any `ModelDocument`, not only one `ObjLoader` produced,
and writes the dialect the loader reads: the same V flip, the same sticky
`usemtl`. This document has no material, so only the `.obj` comes out; a
`.mtl` is written only when the document names one.

{{code write}}

## Step 4: Compare source and output

The source had no normals; the file this page writes does, because a
normal that was generated to satisfy the loader's own request is still a
normal `ObjWriter` will write.

{{code report}}

## Step 5: Check what the page claims

Four faces in, four triangles out, and a generated normal that actually
points somewhere rather than sitting at zero.

{{code check}}
