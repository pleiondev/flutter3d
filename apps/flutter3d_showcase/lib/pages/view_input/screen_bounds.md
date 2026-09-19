# Screen-space bounds

A screen reader needs a rectangle to put a focus ring around. A tooltip
needs one to anchor to. Both are the projection of an object's bounds onto
the glass, and until this function existed every place that needed one built
the matrix and did the divide by hand, three copies of the one step that is
easy to get wrong.

## Step 1: A box in the world

`screenBoundsOfBox` takes an `Aabb3`, not a mesh, so any bounding volume you
already keep for culling or picking works here too.

{{code box}}

## Step 2: Project it

`screenBoundsOfBox` projects all eight corners of the box and returns the
rectangle that covers them, in logical pixels with the origin top left, the
same convention Flutter's own `Rect` uses.

{{code bounds}}

> **Warning.** A box straddling the near plane has no honest rectangle:
> the corners still in front of the eye are a strict subset of what is
> visible, so their box alone would be too small. `screenBoundsOfBox`
> answers the whole viewport in that case rather than something confidently
> wrong.

## Step 3: Read the rectangle

The cube in this page sits in the middle of the view, so the rectangle
`screenBoundsOfBox` returns always covers the middle of the frame. Move the
cube toward an edge and the rectangle would move with it, the way a focus
ring following a selected object needs to.

{{code bounds}}
