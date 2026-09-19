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

## Step 3: Stop and start it

`walk` does nothing when every axis is zero or the toggle turns it off, so
holding still is not a special case: it is calling `walk` with nothing asked
of it.

{{code walk}}

Toggle walking off and the row of posts stops sliding past; the camera is
holding still exactly where the last step left it. `FreeLook` also has a
`look` method, built the same way, that turns the head with the eye held
still instead of the target: it takes the same pixel deltas
`OrbitController.rotate` does.
