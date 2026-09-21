# Walking on terrain

The other four collision shapes are each one convex solid. Ground is not: two
triangles meeting along a ridge make a shape with a dent in it, and no set
of planes describes a dent. `CollisionHeightfield` answers a different
question from the others — which triangles are near this query — and that is
what lets a character controller walk across it exactly the same way it
walks across a box.

## Step 1: A field of samples

Rolling hills, a sample to the metre. Every triangle is extended downward into a solid prism, and where two
prisms meet the shared face is a seam rather than a wall: nothing here stops
a body crossing from one triangle to the next.

{{code field}}

## Step 2: Walk across it

Nothing about `CharacterController` changes for a heightfield. It sweeps and
probes the ground exactly as it does against a box; the shape underneath it
just happens to answer with a different set of planes each time.

{{code walk}}

On the page the walker keeps going: it chases a point a little ahead of itself
on a circle round the field, and the controller carries it up every hill and
down again with its feet on the surface. Drag to turn the view; the camera
follows the walker.

{{code patrol}}

## Step 3: What the feet should be doing

A body standing on sloped ground should have its feet at the ground's own
height under it, not at some average across the field or at the height it
started falling from.

{{code check}}

> **Note.** This package draws nothing. The mesh under the walker on this
> page is built by hand from the same height samples the collision shape
> was given, which is also why the two agree.
