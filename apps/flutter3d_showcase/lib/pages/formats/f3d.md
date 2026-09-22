# The .f3d container

glTF is fast to load because its buffers are already what a GPU wants.
`.f3d` takes that further: it is this engine's own container, built so
loading is almost no work at all, a header read and the rest handed back
as views over the same bytes.

## Step 1: Write it, and a GLB beside it

`F3dWriter` is the offline half of the format, the one
`dart run flutter3d_build:convert` runs once per model. This page also
writes the same sphere as a GLB, only to put a number beside `.f3d`'s
own.

{{code write}}

## Step 2: Read it back

`F3dDocument.parse` reads the header and the section directory to find
where things are. Nothing is decoded eagerly: `surfaces`, once asked for,
is a `Float32List` view over the file's own bytes rather than a fresh
copy.

{{code read}}

## Step 3: Compare the two containers

The numbers below are for the same geometry, written two different ways.

{{code report}}

## Step 4: Check that the round trip held

`compareModelDocuments` reads the geometry back byte for byte, since
`.f3d` is a binary format with no rounding to account for.

{{code check}}
