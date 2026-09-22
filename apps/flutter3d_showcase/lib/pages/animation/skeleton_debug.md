# The skeleton drawn

A skinned mesh hides its own rig: the joints that move it are never drawn,
only the surface they carry. `DebugDrawOptions.skeletons` draws them anyway,
one octahedron a bone and one cross at any joint with no child, over every
skinned mesh in the scene.

## Step 1: The same rig as skinning

Two joints, a base and a tip, and the skeleton built from them. Nothing here
is different from the skinning page; a skinned mesh is what the overlay
needs to find.

{{code rig}}

## Step 2: Ask for the overlay

One setting turns it on. It costs nothing when it is off, and it needs no
change to the mesh or the skeleton to turn on: it reads exactly what is
already there.

{{code settings}}

## Step 3: Compare it against the plain banner

{{source}}

## What to look at

Turn Show skeleton off and the banner looks exactly like the plain skinning
page. Turn it on and two shapes appear over it: an octahedron along the
bone between the base and the tip, and a small cross at the tip itself,
since it has no child of its own. Drag Bend and the overlay follows the mesh
exactly, because both are reading the same joint transforms.
