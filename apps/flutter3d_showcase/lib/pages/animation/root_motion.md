# Root motion

A walk cycle exported with root motion has already had its own forward step
taken out of the animated track: the rig plays in place, and the distance it
would have walked is saved separately. `AnimationPlayer.rootMotionDelta`
reads that saved distance back, a step at a time, so a character controller
can move the object the rig belongs to instead of the rig sliding across the
floor by itself.

## Step 1: A clip whose own track goes nowhere

The track named here has three keys and every one of them is `(0, 0, 0)`.
The values the walk actually had live in `extras` under
`flutter3dRootMotion`, one triple per keyframe, which is where an exporter's
own extraction pass leaves them.

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

{{code live}}

## What to look at

The cube drifts steadily forward. Nothing here moved the cube's own local
transform: the drift is entirely the controller answering
`rootMotionDelta`, frame after frame, for a rig that itself never leaves its
own origin.
