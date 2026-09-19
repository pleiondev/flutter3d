# Draco meshes

Draco is a compressed mesh format most export pipelines can write into a
glTF file, behind `KHR_draco_mesh_compression`. This engine has no Draco
encoder, only a decoder, so this page decodes a real Draco bitstream
rather than building a fake one from scratch.

## Step 1: A real bitstream

This is the exact bytes of a small edgebreaker-encoded mesh, the same
fixture the engine's own decoder tests check against triangles computed
independently. There is no pure-Dart Draco encoder to build this file
with here, only the decoder that reads it.

{{code bitstream}}

## Step 2: Decode it

`decodeDraco` reads both connectivity methods Draco supports, sequential
and edgebreaker, and every prediction scheme a current encoder writes.
This file uses edgebreaker, which carries no index buffer of its own:
both the indices and the vertex order come out however the encoder's
traversal happened to walk the mesh.

{{code decode}}

## Step 3: Turn it into something this engine can draw

A `DracoMesh` is not yet a `MeshData`. Its attributes are keyed by
Draco's own attribute id rather than by name, so a caller picks out the
ones it wants; this page takes positions and recomputes a flat normal per
triangle.

{{code rebuild}}

## Step 4: Check the claim

This particular fixture always decodes to sixty triangles. A decoder that
drifted from that, or that produced no points at all, would be a
different mesh entirely.

{{code check}}
