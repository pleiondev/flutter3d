# Vertex cache ordering

A GPU keeps a small window of recently transformed vertices. A triangle order
that reuses them costs less than one that keeps reaching for a vertex the
cache has already dropped. This page shuffles a mesh's triangles and puts them
back in a cache-friendly order.

## Step 1: Scramble a sphere's triangles

`SphereShape` already produces a fairly local order, so the page shuffles it
first with a fixed seed, to have something worth reordering. The vertices are
untouched; only which triangle is drawn when changes.

{{code scramble}}

## Step 2: Reorder for the cache, then renumber vertices

`optimizeTriangleOrder` scores each triangle by how much of it a simulated
cache still holds and emits the best one first. `optimizeVertexFetch` then
renumbers vertices by the order they are first referenced, so nearby triangles
also read nearby memory. `averageCacheMissRatio` scores an index list before
and after: lower is better, and `3.0` is the worst a random order gets.

{{code reorder}}

## Step 3: Apply the new vertex numbering

The index buffer already changed inside `optimizeVertexFetch`. What is left is
moving each vertex's own floats to its new slot, which is the same permutation
`oldToNew` describes.

{{code rebuild}}

## Step 4: Check the ratio improved

The picture looks identical either way; only the memory access pattern behind
it changed. The page checks that the miss ratio after reordering is no higher
than before.

{{code check}}
