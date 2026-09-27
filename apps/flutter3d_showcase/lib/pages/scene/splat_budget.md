# Splats under a budget

A captured cloud is often millions of Gaussians, and from a distance most of them
cover a pixel or less. Drawing every one of them costs the same whether you can
see the detail or not.

`buildSplatOctree` cuts a cloud into a tree. The leaves are the original splats.
Every node above them holds its children's splats merged into fewer, larger ones.
`SplatLod` then picks a cut through the tree that fits a splat budget: fine where
the cloud is near the eye, coarse where it is far.

## Step 1: A cloud to cut

This page makes its cloud in Dart, so it needs no file: 2400 small round splats
on the surface of a ring, coloured by where they sit. A cloud read with
`parseSplatPly` or from a glTF file goes into the tree the same way.

{{code cloud}}

## Step 2: Build the tree

A box that holds at most `leafCapacity` splats is a leaf. A bigger box is split
into eight, and its own splats are its children's merged on a `grid` by `grid` by
`grid` lattice over the box, so a node holds at most `grid` cubed of them. The
defaults are 512 and 8. This cloud is small, so the page asks for 64 and 4, which
gives the tree a few levels to choose between.

A merged splat is not one of the originals picked to survive. It is a new Gaussian
with the same weighted centre and spread as the splats it replaces, weighted by
their opacity and size, so it covers what they covered.

{{code tree}}

## Step 3: Draw it through a budget

`SplatContributor.lod` draws whatever cut `SplatLod` last chose. The cut starts
at the root and keeps refining the node that looks largest from the eye, its
radius over its distance, as long as that node's children still fit in the
budget. It never holds more splats than the budget. A budget below the root's own
count draws nothing, since there is no coarser cut to give.

{{code contributor}}

## Step 4: Change the budget

The budget is a field, set here every frame from the slider. The cut is not chosen
every frame. It is chosen when the cloud is sorted again: when the eye has moved
far enough, when the cloud moves, when a page of the tree arrives, or when the
budget changes.

{{code budget}}

## Step 5: Try the slider

The slider starts at the root's own count, the coarsest cut there is, and ends
at the whole cloud. Low, the ring is a few dozen soft blobs. Raise it and the side
nearest you sharpens first. At the top every node refines, the cut is the leaves,
and you see the original 2400 splats with nothing merged. Orbit close to one side
at a middle budget and the detail follows you there.

{{code slider}}

## Step 6: Check the cut

After one frame the page checks that a cut was chosen, that it holds no more
splats than the budget, and that at the starting budget it is coarser than the
whole cloud.

{{code check}}

> **Note.** A tree can also be written to a `.f3dsplat` file and read back through
> `PagedSplatOctree`, which asks for deeper pages only where the cut wants them.
> This page keeps the whole tree in memory.
