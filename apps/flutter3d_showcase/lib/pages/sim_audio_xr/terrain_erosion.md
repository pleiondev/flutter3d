# Terrain erosion

Ground made from a formula looks made from a formula: slopes steeper than
loose earth would hold, and no sign that rain has ever fallen on it.
`flutter3d_sim` has two kinds of erosion that work on a `Heightfield`.
`erodeThermally` lets scree slide until no step is steeper than the ground
would hold. `erodeHydraulically` drops rain on the field, one droplet at a
time, and lets each drop carry earth downhill. Both take a field and answer
a new one. Neither adds or removes ground: what leaves one sample is set
down on another.

This page draws one hill twice. The left one is as it was made, and the
right one has been eroded. **Erosion** chooses the kind, and **Droplets** and
**Seed** change the rain.

## Step 1: A hill worth eroding

Thirty-three samples on a side, a metre apart: a cone nine metres high with
a ripple across it. The ripple makes small ridges and valleys for the water
to find. Each slope drops more than half a metre per cell, which is steeper
than the scree will hold.

{{code hill}}

## Step 2: Scree, then rain

`erodeThermally` compares every sample with its four neighbours. Where it
stands more than `talus` metres above one, `rate` of the excess moves down
to the lower ones, in proportion to how much lower each is, pass after
pass. It is the slow kind: frost splitting a cliff and the pieces settling
at their angle.

`erodeHydraulically` follows Beyer's droplet model. A drop lands somewhere
the seed chooses and runs downhill, keeping a little of the way it was
going. It picks up earth where it runs fast and steep, sets it down where
it slows or climbs, and dries as it goes. Whatever it still carries when it
dries, or when it reaches the edge, is set down where it is. The same seed
cuts the same gullies. **Both** runs the scree first, then the rain.

{{code erode}}

## Step 3: What to measure

Three numbers tell whether the ground moved the right way. The total of
all samples is the ground's volume. The peak is the highest sample. The
foot is everything at least twelve metres from the top, which is the ring
the hill's slopes end on.

{{code measure}}

## Step 4: What has to hold

For each kind on its own, and for both together: the volume has to stay
within one part in ten thousand of what it was, the peak has to be lower,
and the foot has to be higher. That is what "moved downhill" means here.
Measured with the page's settings, the foot goes from about 247 to 274
cubic metres for scree, 350 for rain and 372 for both, and the volume
changes in the seventh significant figure, which is float rounding.

{{code check}}

> **Note.** Both kinds work on the whole field at once, on the thread that
> calls them. On a field like this one that takes a few tens of
> milliseconds, and the cost of rain grows with the number of droplets. A
> big field is better eroded off the thread, or once when the level is
> built, than every time it is opened. The droplets run on the samples. A
> gully narrower than a cell does not appear, and a drop that reaches the
> edge of the field sets its load down there, so the rim slowly gains
> ground.
