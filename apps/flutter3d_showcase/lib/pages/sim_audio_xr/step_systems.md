# Systems and events

The engine's loop owns the fixed step, and a game or a plugin adds work to
it by phase without forking anything: `addSystem` puts a function into one
of the loop's phases (`input`, `movers`, `physics`, `fields`, `rules`,
`publish`), and the loop runs it there every step. A genre's own step is one
such system, named `<genre>.step`, and a game orders its rules against it by
that name.

## Step 1: Add systems to a phase

Two systems are added to the `rules` phase here, one that only logs and one
that raises the score. A system names the ones it runs after or before, by
name; registration order decides whatever nothing names.

{{code systems}}

## Step 2: Run a step and hear its events

`runSteps` runs the step's phases in order, each system of a phase in its
place. A system publishes what it did onto a bus, and whoever cares
subscribes. In a game the bus is the loop's own (`LoopContext.publish`), and
a step's events reach the step subscribers at the end of that step, never
across a gap where something else could have changed the world in between.
This page wants each event as it is published, so its bus is a `DirectBus`.

{{code run}}

Logging names scoring as the system it runs after, so scoring runs first even
though logging was added first. The event it published was heard by the
subscriber as it was published.

## Step 3: Remove a system

`addSystem` returns a registration, and cancelling it takes the system back
out. A system removed this way does not run on the next step.

{{code remove}}

## Step 4: Watch the order run

Three systems, added in one order and given another: **scoring** is added
first and named to run after **input**, and **logging** after both. Every
0.6 s a step runs, and each of the three slots lights in the colour of
whichever system ran in that place: blue for input, yellow for scoring,
purple for logging. Turn "scoring before input" on and scoring drops its
constraint, so registration order puts it first; un-register logging and its
slot goes dark. The yellow tower is the score that `scoring` keeps adding to.

{{code live}}
