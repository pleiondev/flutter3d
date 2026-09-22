# Rendering in tiles

A render target has a limit: a screenshot wider than the biggest texture the
device allows cannot be drawn in one pass. `TiledProjection` gets around that
by drawing a large virtual frame one square at a time. Each tile is rendered
as though it were the whole picture, then the tiles are stitched together
afterwards, outside the engine. This page draws every tile into its own cell
of the frame, so the stitched picture is what you see.

## Step 1: A camera to crop

`TiledProjection` wraps another projection rather than replacing it. Anything
that already builds a matrix, perspective or orthographic, can be the base.

{{code base}}

## Step 2: One tile a view

`tileX` and `tileY` say which square of the grid this is; `tilesX` and
`tilesY` say how big the grid is. The projection crops the base matrix's own
`[-1, 1]` cube down to that one square and rescales it to fill the frame
again. Here each tile is a `RenderView` of its own, from the same eye, and
its viewport is the cell of the frame where that piece belongs. Row 0 is the
top of the picture.

{{code tile}}

> **Note.** The aspect ratio passed to a tiled projection is the *stitched*
> picture's aspect, not one tile's. A tile rendered at its own aspect would
> not line up with its neighbours once the pieces are put back together.

## Step 3: Change the grid

Choose a bigger grid and the same picture is made of more, smaller pieces;
at 1x1 there is one tile, and it is the whole picture again, because a single
square that spans the whole cube is no crop at all. Drag **Pull apart** to
open a gap between the cells: the ball, the box and the ring are cut by the
edges of whichever tile they fall across, and put back together at zero.

{{code tile}}
