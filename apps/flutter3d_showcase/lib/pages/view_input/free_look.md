# Free-look and walking

`OrbitController` turns around a point somebody chose. `FreeLook` turns
around the camera's own position instead, and then walks it, which is a
different feel entirely: metres a second rather than radians a pixel. It
does not keep a pose of its own. It drives the same orbit state, with the
eye held still while the head turns and the target sliding while you walk.

## Step 1: Wrap the orbit

`FreeLook` takes the page's existing `OrbitController` and turns its target
into something that walks, rather than replacing it with a second camera.

{{code freelook}}

## Step 2: Walk it

`walk` takes `forward`, `right` and `up` as -1, 0 or 1, the shape a held key
gives, and moves the camera that many `metresPerSecond` along its own axes
for the seconds you hand it.

{{code walk}}

> **Note.** `up` here means the world's up, not the camera's. Rising while
> you look at the floor should lift you off the floor, not push you into it.

## Step 3: Turn the head, then walk

`look` takes the same pixel deltas `OrbitController.rotate` does, but keeps
the eye where it is and slides the target instead. The **Turn the head**
slider feeds it a steady turn every frame, so the camera turns on the spot
and the walk carries it the way it now faces: at zero it walks straight,
and anywhere else it walks a circle.

{{code walk}}

`walk` does nothing when every axis is zero or the toggle turns it off, so
holding still is not a special case: it is calling `walk` with nothing asked
of it. Toggle walking off and the posts stop sliding past while the head
goes on turning; drag **Speed** to change how many metres a second the same
call covers.

The posts are laid out again around the camera every frame, on a lattice
that does not move: a post keeps its place and its colour as you pass it,
and a new one arrives ahead, which is what lets a walk go on for ever in a
scene with nine posts a side in it.
