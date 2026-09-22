# Step, linear and cubic tracks

The same three keyframes, read three different ways. `AnimationTrack` carries
one `AnimationInterpolation`, and that alone decides whether a cube snaps,
ramps or eases between the same two heights.

## Step 1: One track for each interpolation

Step holds the previous key until the next one arrives, so the red cube jumps
rather than moves. Linear blends in a straight line, so the green cube rises
at a constant rate. Cubic spline fits a curve through the keys using an in
and out tangent per key; flat tangents, here, are enough to make it ease in
and out rather than move at a constant rate like the green cube.

{{code tracks}}

## Step 2: One clip, one player, three targets

Every track names a different node index, so one clip drives all three cubes
at once. `AnimationPlayer.targets` is index-aligned with those track node
indices, in the order the cubes were added.

{{code player}}

## Step 3: Advance it

{{code live}}

## What to look at

Watch the moment the bounce starts. The red cube (step) stays on the floor
until the middle of the cycle and then jumps straight to the top. The green
cube (linear) is already rising steadily. The blue cube (cubic) is barely
moving yet: it eases into the rise and eases out of the top, so it starts and
ends slower than the straight line does. Speed changes how fast the whole
cycle plays, not which curve each cube follows.
