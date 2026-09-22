# Meshopt compression

`EXT_meshopt_compression` packs a mesh's vertex and index buffers into a
smaller bitstream a reader has to know the extension to unpack.
`GltfWriter(compressGeometry: true)` reaches for it; this page writes a
sphere both ways and reads the compressed one back.

## Step 1: Write it plain, and compressed

The vertex codec delta-codes each attribute byte lane against the vertex
before it; the index codec exploits the edge a triangle usually shares
with one drawn a few places back. Both bitstreams live in
`meshopt_vertex_codec.dart` and `meshopt_index_codec.dart`; `GltfWriter`
is what reaches for them.

{{code write}}

## Step 2: Confirm the extension was actually used

A GLB's JSON sits as plain text at the front of the file, so whether the
writer actually reached for the extension is a search away rather than a
guess from the byte count alone.

{{code used}}

## Step 3: Read the compressed file back

`GltfLoader` decodes `EXT_meshopt_compression` the same way it decodes an
ordinary accessor, before anything downstream notices a difference.
Reordering a mesh for the GPU's cache moves which byte offset a vertex
lands at without changing what it draws, so the comparison below checks
that the same triangles came back rather than that they are in the same
order.

{{code decode}}

## Step 4: Check the claim

The extension has to actually appear in the file, the geometry has to
survive, and the compressed file has to be smaller than the plain one.

{{code check}}
