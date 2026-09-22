# Sprite-sheet animation

A single sprite makes a particle a shape. A `Flipbook` makes it a small
animation instead: a grid of frames on one texture, one of them showing at a
time depending on how far through its life a particle is.

## Step 1: An atlas of frames

Four cells in a row stand in for four drawn frames of a spark burning out,
from bright to dark. A real atlas would be four pictures; the shape a
`Flipbook` reads is the same either way.

{{code atlas}}

## Step 2: Describe the grid

`Flipbook` only needs to know the grid's shape. `frames` would trim it to
fewer cells than `columns * rows` if the last row were not full; here every
cell is used.

{{code flipbook}}

## Step 3: What a cell is chosen by

A flipbook is driven by how far through its life a particle is, not by a
clock: a long-lived particle and a short one both play the whole sequence
exactly once, which a frames-per-second animation could not promise either
of them.

{{code check}}

> **Note.** This is entirely vertex data. Billboarding already happens on
> the CPU in this engine, so a cell is a rectangle the corner coordinates are
> scaled into before they are written; no shader and no backend had to
> change for a flipbook to exist.
