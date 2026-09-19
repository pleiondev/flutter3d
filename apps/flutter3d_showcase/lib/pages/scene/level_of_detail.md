# Levels of detail

A mesh can lose small details as it shrinks on screen. A model can carry a
coarser stand-in for exactly that moment, and `LodGroup` is what switches to it
and back as the camera moves.

## Step 1: Build the levels as parts

Three spheres share the same radius and origin but use 48, 20, and 8 segments
around the equator. Each becomes a `ModelPart`: a device mesh plus the material
it draws with. This is the same shape a decoded file would arrive in, before
anything ties the parts together.

{{code parts}}

## Step 2: Describe one node with two lower levels

A `ModelNode` names its base surface and, in `lods`, the surfaces that replace
it below a screen fraction. `parts[0]` is the node's own surface; `parts[1]`
and `parts[2]` are named by index inside the two `ModelLod` entries. Wrapping
the parts and the node in a `ModelAsset` is what makes this a model rather than
three unrelated meshes.

{{code asset}}

## Step 3: Instantiate it

`ModelAsset.instantiate` builds the scene nodes for every part. A node whose
surfaces and every level are exactly one mesh each is built as a `LodGroup`
automatically, so there is nothing else to wire up. The group registers itself
with the scene, which is where the page reads it back.

{{code instantiate}}

## Step 4: Let screen size decide

The group measures the mesh bounding sphere through the active projection.
Perspective distance and field of view therefore affect the result together;
an orthographic view uses its visible height instead.

Orbit normally and scroll to zoom. Blue is fine, orange is medium, and red is
coarse.

{{code selection}}

## Step 5: Check the selected level

The page confirms that the group is registered, its active index is valid, and
exactly one child is visible. It also checks that the measured screen fraction
is positive and the chosen mesh reached the frame.

{{code check}}
