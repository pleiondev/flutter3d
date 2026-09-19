# A pose with no scene

Most of this set drives a clip onto scene nodes: `AnimationPlayer` needs
targets, and a target is normally a node in a running scene. `Pose` is the
other half. It is a hierarchy's local transforms as three flat arrays, sampled
straight from a clip with no scene node anywhere in the arithmetic — the
shape a bake, a retarget pass or an offline tool over a thousand frames wants,
where building a scene just to throw it away would be real allocation for a
question that is only arithmetic.

## Step 1: The hierarchy, as arrays

Two joints, a root and a tip, each with a parent index and a rest local
transform. Nothing here is a `SceneNode`.

{{code pose}}

## Step 2: A clip to sample

An ordinary swing on the root's rotation. Rotating a joint never moves the
joint itself, only whatever hangs off it — the same rule a real skeleton
follows — so this is what carries the tip through an arc rather than leaving
it in place. `Pose` reads the track exactly the way `AnimationPlayer` would,
through the same `AnimationTrack.sample`.

{{code clip}}

## Step 3: Sample it, then look at the result

`sampleClip` resets the pose to rest and writes every track's value onto it.
`worldMatrices` composes the whole hierarchy from those local transforms.
Only after both of those does this page read a translation out to place a
marker — the pose itself never heard of the markers.

{{code sample}}

## What to look at

The orange marker swings under the grey one, which never moves: the pose
holds exactly what the clip says and nothing more, whether or not anything is
drawing it.
