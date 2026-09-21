# Terrain in tiles

A `Heightfield` drawn as one surface is fine for a strategy map a few hundred
samples across, and wrong for ground that runs to the horizon: every sample
is drawn whether it covers a hundred pixels or a tenth of one. Cutting the
field into tiles, each buildable at more than one resolution, is how ground
stays cheap far away and detailed up close.

## Step 1: A field to cut up

A small slope, eight cells on a side.

{{code field}}

## Step 2: Cut it into tiles and build one at two levels

`HeightfieldTiles` divides the field into square tiles, each buildable at any
of its levels: level 0 keeps every sample, level 1 keeps every second one.

{{code tiles}}

The coarse build has a quarter of the fine one's grid vertices, because it
keeps every second sample along each axis.

## Step 3: Choose a level by distance

`TileLevelChooser` says which level a tile at a given distance should draw
at, with a band around each threshold so a tile does not flicker between two
levels as the camera drifts across it.

{{code lod}}

A tile close to the camera gets the fine level; one far away gets the coarse
one, which is what keeps a large terrain affordable.

## Step 4: Move the eye over it

The field on this page is thirty-two metres square, cut into sixteen tiles of
eight cells, each of which can be drawn at three levels. The blue ball is the
eye and it circles the field; every frame each tile asks the chooser which level
it should be at, from its own distance to the eye, and is rebuilt only when the
answer changes. The colour says which: green is every sample, yellow every
second, orange every fourth. Narrow **Fine detail within** and the green
patch shrinks round the eye; the skirts hide the seams between levels.

{{code live}}

{{code choose}}

{{code pick}}
