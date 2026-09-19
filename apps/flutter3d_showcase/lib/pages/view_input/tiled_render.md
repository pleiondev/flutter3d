# Rendering in tiles

A render target has a limit: a screenshot wider than the biggest texture the
device allows cannot be drawn in one pass. `TiledProjection` gets around that
by drawing a large virtual frame one square at a time. Each tile is rendered
as though it were the whole picture, then the tiles are stitched together
afterwards, outside the engine.

## Step 1: A camera to crop

`TiledProjection` wraps another projection rather than replacing it. Anything
that already builds a matrix, perspective or orthographic, can be the base.

{{code base}}

## Step 2: Ask for one tile

`tileX` and `tileY` say which square of the grid this is; `tilesX` and
`tilesY` say how big the grid is. The projection crops the base matrix's own
`[-1, 1]` cube down to that one square and rescales it to fill the frame
again.

{{code tile}}

> **Note.** The aspect ratio passed to a tiled projection is the *stitched*
> picture's aspect, not one tile's. A tile rendered at its own aspect would
> not line up with its neighbours once the pieces are put back together.

## Step 3: Change the grid

Choosing a bigger grid narrows what one tile shows; moving the column and row
sliders walks across it. At a 1x1 grid there is only one tile, and it is the
whole picture again, because a single square that spans the whole cube is no
crop at all.

{{code tile}}
