# Fixed step and interpolation

A game that updates its physics on every rendered frame runs at a different
speed on every screen. A monitor at 144 hertz applies gravity more often than
one at 60 hertz, so the same jump reaches a different height. The fix is to
step the simulation by a fixed amount of time, however often the frame arrives,
and to smooth the picture between two simulated states so it still looks
fluid.

## Step 1: Accumulate real time into fixed steps

`FixedStep` takes however many seconds a frame actually took and hands back
how many whole steps of simulated time fit into it. Leftover time waits for
the next call, so nothing is lost to rounding over a long session.

{{code clock}}

`InterpolatedVector3` remembers the last two positions the simulation
produced, so the renderer can draw somewhere between them.

## Step 2: Decide whether to step at all

Not every frame should advance the game. `shouldPause` looks at whether a menu
is open, whether the pointer is what holds the player's attention, and whether
a pad is connected, and answers from those facts rather than from a single
flag that someone forgets to set.

{{code gate}}

## Step 3: Run the steps a frame is owed

Each call to `advance` can return more than one step, if the last frame ran
long, or none at all, if the display outpaces the simulation. Every step this
page runs moves a marker along a line and hands the new position to the
interpolator.

{{code advance}}

## Step 4: Draw between two states

`alpha` says how far the next frame sits between the last two steps, from 0 to
just under 1. Reading it blends the two positions, so the marker moves
smoothly even when the simulation is stepping less often than the screen
draws.

{{code blend}}

Turn on "Menu open" and the marker stops advancing entirely: `shouldPause`
reports true, and the step is skipped rather than being fed zero seconds.
