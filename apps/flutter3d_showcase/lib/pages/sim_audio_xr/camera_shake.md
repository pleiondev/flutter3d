# The shared camera rig

A platformer's chasing view and a racing game's both ease towards where they
should be, both carry a landing's knock or an explosion's shake as it fades,
and both have to stay out of the walls. `CameraRig` is that part, written
once; what differs between the two games is only how each works out where
the rig should be looking.

## Step 1: The six numbers a chase needs

`RigTuning` is a base class a game extends with its own tuning. This page's
is a short chase behind a fixed point.

{{code tuning}}

## Step 2: Build the rig

`CameraRig` needs a collision world to stay out of, even an empty one.

{{code rig}}

## Step 3: Place it every frame

`place` eases the rig's eye towards a desired position and a desired target,
and folds in any pending knock or shake. Turning on "Kick the rig" adds both
a downward knock and a short shake, the way a hard landing would.

{{code place}}

## Step 4: Let it settle

{{code settle}}

Left alone with nothing kicking or shaking it, the rig's shown position
converges on the same free eye it is chasing, because there is nothing to
pull it away from that and nothing in its way.
