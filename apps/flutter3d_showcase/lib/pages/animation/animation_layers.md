# Layers and masks

A crossfade moves the whole skeleton from one clip to another. Sometimes only
part of it should change: an arm waving while the body keeps walking. That is
what a layer is for, and `AnimationMask` is how it says which joints it may
touch.

## Step 1: Two clips that both mention the arm

The base clip, walk, animates the body and the arm both. The layer clip,
wave, only has a track for the arm. Both tracks address the same node index,
so they compete for the same joint.

{{code clips}}

## Step 2: A layer masked to one joint

`playLayer` starts the wave clip as a layer over the base. The mask names
node 1, the arm, and nothing else: the body keeps playing whatever the base
clip says regardless of what the layer does.

{{code layer}}

## Step 3: Advance the player

A layer has its own playhead, but it only moves when the player is asked to.

{{code live}}

## What to look at

The body keeps its own small tilt from the walk clip the whole time: the mask
never lets the layer near it. The arm, though, follows the wave clip and
nothing of the walk clip's own arm swing shows through, because a layer with
full weight replaces the base's value for the joints it covers rather than
blending with it.
