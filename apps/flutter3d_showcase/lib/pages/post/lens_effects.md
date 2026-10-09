# Lens effects

Three things a real lens does to a picture, all of them settings on the
composite or the glow. A very bright light throws ghosts and a ring across the
frame. The glass bends the frame, outwards like a wide lens or inwards like a
long one. And a colourist hands over a grade as a `.cube` file, which the
engine reads as it is.

This page puts a lamp far brighter than the display in the top left of the
post-processing stage and runs all three over it.

## Step 1: A light bright enough to flare

The flare is drawn from the glow, so only what blooms flares. The lamp is a
small sphere with an emission forty times over the display's white, placed so
that the line from it through the middle of the frame crosses the shapes on
the floor. Nothing else in the scene is bright enough to throw a ghost.

{{code lamp}}

## Step 2: Turn on the flare and bend the frame

`BloomSettings.lensFlare` takes a `LensFlareSettings`. With it enabled, the
glow's bright spots are reflected through the middle of the frame as a row of
ghosts, each with its colours pulled slightly apart at the rim, and a ring is
drawn at `haloRadius` from the middle. `halo` is the ring's strength against
the ghosts; nought draws none. A ghost is as soft as the glow it is drawn
from, so this page asks for three bloom levels instead of five. With five,
the ghosts spread into a wash across half the frame.

`LookSettings.distortion` bends the frame radially about its middle. Above
nought is barrel, the corners held and the middle pushed out; below nought is
pincushion. The bend is applied once in the composite, before anything is
read, so the glow and the flare bend with the scene. The vignette, the grain
and the dither do not move, because they belong to the film and not to the
glass. Drag **Distortion** through nought to see it change direction.

{{code lens}}

## Step 3: Tables from a grading tool

A `.cube` file is plain text: a size, then one line of three numbers per
entry, red changing fastest. The warm table here is the smallest 3D table
there is, the eight corners of the colour cube, and every colour between them
is blended from those corners. The curve is a 1D table, one S curve applied to
each channel on its own. Both are written inline, but a file read with
`rootBundle.loadString` goes through the same call.

{{code tables}}

`CubeLut.parse` reads the text and throws a `FormatException` naming the line
when something is wrong with it. `upload` resamples whatever the file holds
into the strip that `LookSettings.lut` grades through, and puts it on the
device. Pick a table with **Table**.

{{code load}}

## Step 4: What the page checks

The flare has to have run as a pass of its own. The warm table has to give
back the file's own numbers at the white corner and turn a middle grey warmer
than it went in, with more red than blue. The uploaded table has to have
reached the device, and the composite, which bends the frame and reads the
table, has to have run.

{{code check}}

> **Note.** The check reads the table and the pass list, not the pixels: the
> claim that the flare lands where the ghosts should is held by the
> `lens-flare` and `lens-distortion` reference images, recorded on all four
> backends. There is no anamorphic streak yet, and no starburst from an
> aperture texture. The table is applied after the picture is encoded for the
> display, so values outside nought and one are clamped before it reads
> them.
