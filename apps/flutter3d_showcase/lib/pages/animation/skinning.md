# Skinned meshes

A skinned mesh is an ordinary mesh whose vertices are also told which joints
move them, and by how much. The engine keeps two things: a `Skeleton`, which
turns a chain of scene nodes into the matrices the device reads, and
`SkinBlend`, a CPU copy of the same arithmetic. This page builds a two-joint
banner and bends it with the Bend slider.

## Step 1: Two joints, one skeleton

A joint is a plain `SceneNode`. The tip is a child of the base, offset along
the banner's length, so rotating the tip bends everything past it rather than
the whole banner. `Skeleton` needs the inverse of each joint's bind-pose world
matrix, taken right after the hierarchy is built and before anything moves it.

{{code rig}}

## Step 2: Paint the weights

A mesh built by `PlaneShape` carries no joints or weights, so the first step is
converting it to the layout that has them. Every vertex then gets an index
pair, `[0, 1]`, and a weight pair that blends smoothly from all base near one
end to all tip near the other: `t` is how far along the banner the vertex sits.

{{code weights}}

## Step 3: Attach the skeleton to the mesh

A `MeshNode` draws with its `skeleton` set, and nothing else marks it as
skinned. The renderer reads the skeleton's matrices once a frame and uploads
them; the CPU-side `_cpuMesh` this page keeps is only for `SkinBlend` to check
its own claim afterwards, not for drawing.

{{code mesh}}

## Step 4: Move a joint

Bending the banner is one line: turn the tip joint. The base never moves, so
the near half of the banner stays put and the far half swings with the tip.

{{code live}}

Drag Bend and watch the far half of the banner swing while the near half stays
planted. `SkinBlend` recomputes the same bend on the CPU every time the page's
own check runs, and the two are held to agreeing with each other.
