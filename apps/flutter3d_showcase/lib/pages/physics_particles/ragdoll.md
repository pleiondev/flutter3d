# A ragdoll

A ragdoll is a body made of capsules, one for each bone, joined where each
bone meets its parent. Each joint lets its bone turn only as far as the
joint it stands for: a knee bends one way, a shoulder swings in a wide cone.
`NativeRagdoll` builds one in the physics core from a list of bones given in
world space. It knows nothing about scenes or skinned models, so a page can
make one from a dozen numbers.

This page stands a figure of eleven bones at the top of four steps, shoves
it in the chest and lets it fall. Ragdolls exist only on the core. Where the
core will not start, the page shows the stairs and says why beside the
viewport.

## Step 1: The bones

A `RagdollBone` has a name, the index of its parent (−1 for the root, and
always an earlier bone), a head where it meets the parent, a tail where its
capsule ends, a radius and a mass. Its `joint` says how it is held to its
parent. `RagdollBall` is a ball joint with a cone for the swing and limits
on the twist, for the spine, neck, shoulders and hips. `RagdollHinge` is a
hinge about an axis in the bone's own frame, from a lower to an upper angle,
for elbows and knees.

{{code figure}}

## Step 2: The world, and the ragdoll in it

The floor and the steps are fixed boxes. The ragdoll is made in the world
with `NativeRagdoll(world, bones)`: one capsule for each bone and one joint
where each bone meets its parent. The joints' limits are taken from the pose
the bones are given in, so a ragdoll is built standing and only then moved
into another pose with `place`. This one is not moved at all.

Every joint resists turning with two newton metres by default. Without that
friction a ragdoll lying on the floor never stops moving, because nothing
slows a head rolling or a leg turning about its own length. The world takes
eight substeps a step instead of four. With four, an arm hitting the edge of
a step can swing past its cone for a step.

{{code world}}

## Step 3: The push

`bodyOf` gives the core's body for a bone, and an impulse on the chest
pushes the whole figure. **Push it again** wakes it and pushes it once more
from wherever it lies.

{{code push}}

## Step 4: Draw each bone as its capsule

A ragdoll's capsule lies along its body's own y axis, and its straight part
is the bone's length less a radius at each end. So each bone is drawn as a
`CapsuleShape` of that size, placed each frame at its body's position and
orientation. `poseOf` would give the bone's own frame instead, for a skinned
model whose rig chose its own axes.

{{code bones}}

## Step 5: What it has to do

The check pushes the figure again and steps until every bone is asleep,
giving up after fifteen seconds. After every step it measures each bone's
head against its parent's and compares the distance with the one the bones
were built with. No joint may open by more than three centimetres on the way
down. The hips have to end at least half a metre lower than they started,
and no bone may end inside the floor. On macOS the figure sleeps after about
four and a half seconds, and no joint opens by more than six millimetres.

{{code check}}

> **Note.** The joints are soft. A joint can open by a few centimetres for a
> step when a limb hits hard, and a limb can go a few degrees past its
> limit, before the solver pulls it back. At rest the error is a fraction of
> a millimetre. The figure here is made of plain capsules with no hands or
> feet, so it slides on the steps more than a body would. For a skinned
> model, `SkeletonRagdoll` builds the bones from the model's skeleton and
> writes the bodies back into its joints.
