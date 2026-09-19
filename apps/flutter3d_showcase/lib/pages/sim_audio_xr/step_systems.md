# Systems and events

A genre package owns its own step, but a game built on top of it often wants
to hang extra work off a point in that step without forking it. `StepSystems`
is that seam: a game registers a function against a phase, and the genre
announces the phase without needing to know what the game hung there.

## Step 1: Register systems against a phase

Two systems are added to the same phase here, one that only logs and one that
raises the score. `order` decides which runs first; registration order only
breaks a tie.

{{code systems}}

## Step 2: Run the phase and drain its events

`run` calls every system registered for a phase, in order. `GameEvents` is a
buffer a system writes into and a frame reads afterwards, in the same step,
never across a gap where something else could have changed the world in
between.

{{code run}}

The scoring system has the lower `order`, so it runs before the logging
system even though logging was registered first. The event it raised is still
sitting in the buffer until something drains it.

## Step 3: Remove a system

`add` returns a handle, and that handle is what takes the system back out
again. A system removed this way does not run on the next step.

{{code remove}}
