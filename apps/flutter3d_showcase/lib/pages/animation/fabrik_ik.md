# A chain of any length

Two bones are one shape; a tail, a rope or a tentacle is a chain of however
many the rig has. `FabrikIk` solves that general case: pin the tip to the
target, walk backward re-placing each joint at its fixed distance from the
next, then pin the root back where it started and walk forward the same way,
repeated until the tip is close enough or the iteration budget runs out.

## Step 1: A chain, not a fixed shape

Building the pose is the same idea as two-bone IK, just for however many
joints `_jointCount` says. Nothing about `Pose` or `FabrikIk` knows there
used to be a fixed shoulder-elbow-wrist story here.

{{code chain}}

## Step 2: Solve it every frame

`FabrikIk.solve` takes the joint list root to tip and a target, and moves
every one of them. The result still only exists on the pose until it is
written onto the beads this page draws.

{{code solve}}

## Step 3: Watch the last bead answer

The same lines from step 2 measure the tip's own distance from the target
after solving, which is what this page checks against on every frame.

{{code solve}}

Drag Reach and follow the orange bead, the tip of the chain. The chain bends
smoothly along its whole length rather than concentrating the bend at one
joint, which is what a rope or a tail is expected to look like.

## What to look at

Push Reach toward one and the chain straightens into nearly a single line
reaching for the target; pull it back and the chain curls, since a shorter
reach leaves the solve more freedom in how it distributes the bend along
four joints instead of two.
