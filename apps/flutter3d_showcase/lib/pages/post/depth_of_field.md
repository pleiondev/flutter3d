# Depth of field

A camera lens has exactly one distance in perfect focus, and everything else
softens by an amount that follows from the lens itself: how far away it is
focused, how long the lens is, and how wide the aperture is open. This page
takes the same three numbers a photographer already knows instead of a single
blur slider.

## Step 1: Something at many distances

Six posts stand in a row, each one two metres further than the last, so the
picture holds near, focused and far all at once.

{{code row}}

## Step 2: Set the lens

`focusDistance` is what the lens is focused on, in metres. `focalLength` is the
lens length in metres, 0.085 for an 85mm portrait lens. `aperture` is the
f-number: a small number like 1.4 is wide open and blurs hard, a large one like
16 is a pinhole and keeps almost everything sharp.

{{code lens}}

Drag Focus distance and watch which post is sharp. Drag Aperture down toward
1.4 and the posts on either side of it soften quickly; drag it up toward 16 and
the whole row sharpens. Focal length is the strongest of the three, because it
enters the blur formula squared: a long lens throws the background out of
focus at an aperture where a short one would keep it sharp.

## Step 3: Confirm the lens ran

{{code ran}}

> **Note.** The blur reads distance from the surface buffer's own depth
> channel, in real metres rather than a screen-space guess, which is why the
> numbers above behave the way a lens actually does.
