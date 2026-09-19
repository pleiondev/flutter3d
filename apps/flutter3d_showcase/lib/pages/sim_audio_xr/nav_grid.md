# Path-finding

Before anything can path across a level, something has to say where standing
is possible at all. `NavGrid` bakes that once from the level's brushes into a
lattice of cells, so a step asks "can I stand here" and "can I move from here
to there" as array lookups instead of geometry queries.

## Step 1: Build a small level

Two floor slabs with a narrow bridge between them, and open air everywhere
else.

{{code brushes}}

## Step 2: Bake the grid

`NavGrid.bake` rasterises the solid brushes into cells at a chosen size,
finding the floor height and the headroom above it for each one.

{{code bake}}

## Step 3: Ask it questions

`cellAtPoint` finds which cell a world position falls in, and `isWalkable`
says whether anything can stand there.

{{code query}}

Both slabs and the bridge between them answer walkable; the open gap on
either side of the bridge does not, because no brush covers it.
