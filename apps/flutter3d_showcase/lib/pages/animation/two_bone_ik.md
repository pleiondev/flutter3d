# Two-bone IK

An arm bends so its hand reaches a point without anyone hand-animating the
elbow. `TwoBoneIk` does the bending: given a target and which side the elbow
should point to, it solves the shoulder and elbow rotations that put the
wrist there.

## Step 1: A pose with three joints, nothing else

`TwoBoneIk` works on a `Pose`: three local transforms and a parent index
each, no scene node in sight. The shoulder is the root, the elbow is its
child, the wrist is the elbow's child, each one bone-length below the last.

{{code pose}}

## Step 2: Solve, then write it onto something to draw

Every frame the pose is put back to rest, solved fresh for the current
target, and only then written onto three real nodes so this page has
something on screen. The solve itself never touched a node.

{{code solve}}

## Step 3: A target that never breaks the reach

The same lines from step 2 clamp the target to what the two bones can
actually stretch or fold to before solving anything: a point too far away is
treated as being exactly at the arm's full length, and one too close is
treated as being exactly at the shortest fold. There is no target this page
can ask for that leaves the wrist unable to answer.

{{code solve}}

## What to look at

The red marker is the target. Drag Reach and watch the wrist follow it: the
elbow bends further as the target moves closer and straightens as it moves
away, always on the side the pole vector names.
