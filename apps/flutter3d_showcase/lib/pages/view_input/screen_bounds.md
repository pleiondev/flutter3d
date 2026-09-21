# Screen-space bounds

A screen reader needs a rectangle to put a focus ring around. A tooltip
needs one to anchor to. Both are the projection of an object's bounds onto
the glass, and until this function existed every place that needed one built
the matrix and did the divide by hand, three copies of the one step that is
easy to get wrong.

This page moves a cube, a sphere and a pillar about a floor and draws the
rectangle `screenBoundsOfBox` returns for each, with its position and size in
pixels, over the picture. Drag to orbit and scroll to zoom: the rectangles
follow.

## Step 1: A box in the world

`screenBoundsOfBox` takes an `Aabb3`, not a mesh, so any bounding volume you
already keep for culling or picking works here too. The three boxes are built
from where each thing is this frame.

{{code box}}

## Step 2: Project it

`screenBoundsOfBox` projects all eight corners of the box and returns the
rectangle that covers them, in logical pixels with the origin top left, the
same convention Flutter's own `Rect` uses. The size handed in is the size the
frame is shown at, so the rectangle lands on the picture at any window size.

{{code bounds}}

> **Warning.** A box straddling the near plane has no honest rectangle:
> the corners still in front of the eye are a strict subset of what is
> visible, so their box alone would be too small. `screenBoundsOfBox`
> answers the whole viewport in that case rather than something confidently
> wrong.

## Step 3: Read the rectangle

A rectangle is only as tight as the box it came from. The cube's box hugs it
when it faces the camera square on; a box projected from an angle covers the
cube's corners and a little of the air around them, which is why the ring
around a sphere is always a touch larger than the sphere. That is the price
of projecting eight corners instead of every vertex, and the reason it is
cheap enough to do for everything on screen every frame.

{{code bounds}}
