# Writing GLB

`GltfWriter` turns any `ModelDocument`, however it was decoded, into a
self-contained GLB. This page writes the same sphere twice, once plain and
once with `compressGeometry`, and compares the two files it gets back.

## Step 1: A document with something worth compressing

A sphere with forty-eight segments has enough vertices that reordering them
for the GPU's cache and packing their attributes into smaller types
actually saves bytes. A cube would be too small to show the difference.

{{code document}}

## Step 2: Write it twice

`GltfWriter.writeGlb` is the whole encode: geometry, the one material, and
the header around them. `compressGeometry: true` asks for two independent
things on the way out, reordering the mesh for the GPU's post-transform
cache and packing normals and texture coordinates as normalized integers
instead of floats.

{{code write}}

> **Note.** `compressGeometry` never touches `POSITION`. Making that safe
> needs a per-mesh dequantization scale baked into every node that draws
> the mesh, and a node can draw more than one surface without a box they
> all share, so this writer leaves positions as plain floats rather than
> quantize them incorrectly.

## Step 3: Read the numbers back

`GltfWriter` says, after writing, whether the compression actually did
anything: `usedGeometryQuantization` and `usedVertexCacheReordering` are
both false only when a document has nothing for them to change.

{{code report}}

## Step 4: Check the file, not just the byte count

A smaller file that starts with the wrong bytes is not a GLB at all. This
page's claim is three things at once: the file starts with glTF's own
magic, the compressed file is smaller than the plain one, and the sphere
that both describe actually got drawn.

{{code check}}
