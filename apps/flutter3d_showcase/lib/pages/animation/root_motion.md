# Root motion

A walk cycle exported with root motion has already had its own forward step
taken out of the animated track: the rig plays in place, and the distance it
would have walked is saved separately. `AnimationPlayer.rootMotionDelta`
reads that saved distance back, a step at a time, so a character controller
can move the object the rig belongs to instead of the rig sliding across the
floor by itself.

## Step 1: A clip whose own track goes nowhere

The track named here bobs up and down and goes nowhere: its keys are all at
`x = 0, z = 0`. The forward travel the walk actually had lives in `extras`
under `flutter3dRootMotion`, one triple per keyframe, which is where an
exporter's own extraction pass leaves it.

{{code clip}}

## Step 2: A controller to carry it

The walker mesh is a child of a separate node, the controller. The player
only ever moves the walker's own flattened track, so the walker stays still
inside the controller's space; the controller is what root motion is going
to move instead.

{{code controller}}

## Step 3: Read the delta and carry it

Each frame asks the player how far the walk would have moved between the
playhead's last position and its new one, and adds that to the controller.
The clip only ever walks forward, so when the controller reaches the end of
the floor it is the controller that turns round and sends the same delta the
other way.

{{code live}}

## What to look at

The cube walks to one end of the floor, turns, and walks back, over and over.
Nothing here moved the cube's own local transform except the little bounce in
the clip's own track: the trip is entirely the controller answering
`rootMotionDelta`, frame after frame, for a rig that itself never leaves its
own origin. The posts along the edge are what show it — the walker's own
shape never changes, and the ground goes past it.
