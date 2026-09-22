# Cardboard viewer profiles

A lens does not sit in the middle of the half of the screen it looks
through: it sits nearer the middle of the phone, because the two lenses are
a face's width apart and a phone is wider than that. `StereoViewer` carries
the numbers a holder differs by — how far apart the lenses are, how far the
screen sits from them, how high the lens axis is above the tray, and how
wide the lens lets the eye see.

## Step 1: Pick a profile

`cardboardV1` is the older, narrower holder; `cardboardV2` is the one most
folded holders since have copied.

{{code viewer}}

## Step 2: Apply it to the rig

`applyViewer` turns a viewer's numbers and a screen's size into an
off-centre frustum per eye, wider away from the nose than towards it.

{{code apply}}

## Step 3: Compare the two

{{code compare}}

The older holder's lenses let through a narrower slice of the world than the
newer one's, at the same screen — which is the whole reason the four numbers
are worth carrying separately instead of guessing one frustum for every
holder.
