# BVH and frustum culling

Submitting a mesh that cannot reach the image wastes CPU and GPU work. The
render list tests world-space boxes against the view frustum and uses a BVH
once a scene is large enough to benefit from the index.

## Step 1: Keep a small group in view

Sixteen cubes form the part of the scene the camera can see. They share one
mesh and material, but remain separate nodes so each has its own world bounds.

{{code visible}}

## Step 2: Put a large branch outside the frustum

Another 304 cubes sit under one parent far from the view. The parent's
`subtreeBounds` encloses the whole warehouse, allowing a branch-level test to
reject it before every child needs individual work.

{{code offscreen}}

## Step 3: Light only what survives

Lighting happens after visibility is decided. The directional light therefore
reaches the visible cubes without turning the offscreen warehouse into draw
calls.

{{code light}}

## Step 4: Read the culling result

`FrameResult.culled` reports how many scene meshes did not enter the colour
pass. The page checks the full scene size, the branch bound, and that at least
all 304 offscreen cubes were rejected.

{{code check}}
