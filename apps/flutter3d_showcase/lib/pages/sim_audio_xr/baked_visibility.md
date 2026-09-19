# Baked visibility

A brush level is boxes, so whether one point can see another through the
walls is a question the collision world already answers exactly. Baking that
answer once, into a table keyed by cell, means a frame does not raycast to
find out: it looks up which cell the camera is in and which other cells that
cell can see.

## Step 1: A corridor with a wall across it

One long floor, and a wall crossing it a third of the way down with no gap
in it.

{{code level}}

## Step 2: Bake the table

`LevelVisibility.bake` samples points inside each cell of a grid over the
level and traces rays between them through the level's own collision world.

{{code bake}}

## Step 3: Hide what the eye cannot see

`VisibilityCuller` is the runtime half: given the table and a list of
batches with their bounds, it turns a batch's mesh node off when the eye's
own cell cannot see it.

{{code cull}}

Standing on the near side of the wall, the culler leaves the near marker
showing and turns the far one off, because every straight line from one side
to the other has to cross the wall.
