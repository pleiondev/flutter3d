# Morph targets

A morph target is a set of deltas: how far each vertex moves, added to its
base position by some amount from nought to one. This page builds a flat
sheet and one target that lifts its middle into a bump.

## Step 1: Deltas for one target

The target is the same shape as the mesh, but its numbers are offsets rather
than positions. Here only Y moves, most in the middle and less toward the
edges, which is what a gaussian falloff gives for free.

{{code target}}

## Step 2: Pack the deltas into a texture

The deltas do not travel as a second set of vertex attributes: `MorphTexture`
packs them into a float texture instead, one column a vertex, so a lighting
model does not need a second vertex shader to read them.

{{code texture}}

## Step 3: Weigh it

`MorphState` holds how much of each target is showing, from nought to one,
and it lives on the node rather than on the mesh: two copies of one sheet can
wear different bumps from the same uploaded deltas.

{{code morph}}

## Step 4: Change the weight while it runs

{{code live}}

Drag Weight from nought to one and watch the bump rise out of a flat sheet.
At nought the sheet is exactly the base mesh; the deltas are being added, not
substituted, so a weight of nought costs nothing and changes nothing.
