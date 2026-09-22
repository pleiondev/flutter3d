# STL

STL is the format a 3D printer's slicer reads: a flat list of triangles,
no shared vertices, no materials, no hierarchy. This page reads a small
ASCII file and writes the binary form back out.

## Step 1: A file whose facets do not trust their own normals

Every facet in STL carries its own normal, ahead of its three vertices.
This one sets every normal to zero on purpose, which is what a
surprising number of real exporters actually write.

{{code source}}

## Step 2: Decode it

`StlLoader` reads both dialects: it tells binary from ASCII by the file's
own size arithmetic, not by whether the text starts with `solid`, because
a binary file's free-text header often starts with that word too.
`StlNormals.fromFile`, the default, falls back to the triangle's own cross
product whenever the file's normal is the zero vector.

{{code load}}

## Step 3: Write it back as binary

`StlWriter` bakes every surface's transform into its positions, since STL
has no per-object placement to carry it in, and writes one flat facet
list either as compact binary or as text.

{{code write}}

## Step 4: Compare the two files

The ASCII source and the binary output describe the same four triangles
in very different numbers of bytes.

{{code report}}

## Step 5: Check the claim

Four facets in, four facets out, every normal actually pointing
somewhere, and a binary file exactly the size its own header formula
says four facets should be.

{{code check}}
