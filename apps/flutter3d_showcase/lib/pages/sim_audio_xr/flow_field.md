# A flow field

When every agent in a level chases the same target, running one path search
per agent recomputes most of the same tree over and over. A flow field turns
that around: it sweeps once from the goal, and every cell ends up holding the
direction that leads there. Steering an agent is then one array lookup.

## Step 1: A grid to sweep over

An open floor, ten metres on a side.

{{code grid}}

## Step 2: Sweep towards a goal

`FlowField` wraps a grid, and `rebuild` runs the sweep towards a world
position. It only needs re-running when the goal moves to a different cell,
or when the level itself changes.

{{code field}}

## Step 3: Ask which way to walk

`descend` writes the direction to walk from any point, as a flat unit vector.
`walkingDistanceTo` reports how far it is to the goal along the field, which
the sweep already knows for free.

{{code descend}}

A point in the near corner of the floor is told to walk towards the far
corner, where the goal sits.
