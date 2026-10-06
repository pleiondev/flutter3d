# A world of blocks

A sandbox's state is its blocks, and there are a lot of them: this small
world is thirty-two by sixteen by thirty-two, sixteen thousand voxels. Saving
every one of them would be wasteful when almost all of them are still what
the terrain put there. So a `VoxelWorld` keeps the terrain as a seed and a
few numbers, and the edits as a list of the voxels that differ from it.

## Step 1: Ground from a seed

The world is cut into chunks sixteen voxels on a side, a byte a voxel.
`VoxelTerrain` draws rolling ground from a `GameRandom` stream, mixed with
nothing but adding and multiplying, so two machines given seed 7 draw the same
ground bit for bit. The save taken here, before anything is edited, holds the
world's size, the terrain's numbers and an empty list of edits.

{{code world}}

## Step 2: Boxes to collide with

`VoxelCollision` covers each chunk's solid voxels with as few boxes as it can
find and puts them in an ordinary `CollisionWorld`. Nothing in the physics
knows about voxels. The world is attached to the run's physics, so on the
native core the same boxes are mirrored there by revision.

{{code collision}}

## Step 3: Faces as greedy meshes

`meshChunk` draws a face only where a block meets air, and merges the faces
of one slice that look the same way and are the same material into the fewest
rectangles. A flat patch of grass sixteen voxels square is two triangles, not
five hundred. It reads across chunk borders, so a wall running over one has
no seam. One mesh comes back per material, and each becomes a node here.

{{code mesh}}

## Step 4: An edit costs its chunk

`edit` changes one voxel and remembers which chunks it touched.
`takeChanges` hands those over: `surfaces` are the chunks whose faces may have
changed, which includes a neighbour when the voxel sits on a border, and
`chunks` are the ones whose boxes did. Nothing else is meshed or rebuilt.

The page digs a pit five blocks wide and four deep in the middle, a block at a
time, then builds a tower of brick, a material the terrain never lays. Turn
off **Dig and build** to stop it.

{{code edit}}

## Step 5: Put the save back

`restoreEdits` takes a save and touches only the voxels that differ from it.
Restoring the save from Step 1 fills the pit and takes the tower down, then the
page starts digging again. **Put back the save** does it at once.

{{code restore}}

## Step 6: What the page checks

A ray down onto the boxes finds the top of a column; after its top block is
dug out the ray finds the block under it, and the chunk's mesh has changed.
Edited back to what the terrain had, the voxel is no edit at all. A world read
back from its save has the same digest as the one that wrote it, and after the
first save is restored the world is the terrain again.

{{code check}}

> **Note.** `raycast` on the world picks a block through the grid rather than
> the merged boxes, since a box says where a ray stopped but not which voxel
> it was, and `before` on the hit is where a placed block goes.
> `VoxelNavigation` keeps a navigation mesh in step with the digging, baking
> again only the tiles an edit reaches.
