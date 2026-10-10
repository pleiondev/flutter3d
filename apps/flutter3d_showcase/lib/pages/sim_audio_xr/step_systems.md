# Systems and events

A genre package owns its own step, but a game built on top of it often wants
to hang extra work off a point in that step without forking it. `StepSystems`
is that seam: a game registers a function against a phase, and the genre
announces the phase without needing to know what the game hung there.

## Step 1: Register systems against a phase

Two systems are added to the same phase here, one that only logs and one that
raises the score. A system names the ones it runs after or before, by label,
the same way the engine's loop orders its own; registration order decides
whatever nothing names.

{{code systems}}

## Step 2: Run the phase and hear its events

`run` calls every system registered for a phase, in order. A system publishes
what it did onto the bus, and whoever cares subscribes. In a game the bus is
the engine's, and a step's events reach the step subscribers at the end of
that step, never across a gap where something else could have changed the
world in between. This page runs the phase by hand, without an `EngineLoop`,
so its bus is a `DirectBus`, which hands each event out as it is published.

{{code run}}

Logging names scoring as the system it runs after, so scoring runs first even
though logging was registered first. The event it published was
heard by the subscriber as it was published.

## Step 3: Remove a system

`add` returns a handle, and that handle is what takes the system back out
again. A system removed this way does not run on the next step.

{{code remove}}

## Step 4: Watch the order run

Three systems, registered in one order and given another: **scoring** is
registered first and named to run after **input**, and **logging** after both.
Every 0.6 s a step runs the phase, and each of the three slots lights in the
colour of whichever system ran in that place: blue for input, yellow for
scoring, purple for logging. Turn "scoring before input" on and scoring drops
its constraint, so registration order puts it first; un-register logging and
its slot goes dark. The yellow tower is the score that
`scoring` keeps adding to.

{{code live}}
