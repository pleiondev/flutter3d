# Convex shapes and mesh floors

The physics core has more shapes than a box, a ball and a capsule. It has
cylinders and cones, convex hulls built from a list of points, and any of
these rounded by a radius. For level geometry it has triangle meshes, which
only fixed bodies can be. This page drops one of each on a mesh: a cylinder
rolls down a ramp, a cone and a rock land and stay put, and a rounded box is
thrown spinning and tumbles before it settles.

These shapes exist only on the core. Where the core will not start, the page
shows the ground and says why beside the viewport.

## Step 1: The ground is a triangle mesh

A mesh is a list of vertices and three indices for each triangle. Each
triangle is wound counter-clockwise when seen from the side bodies touch,
because a mesh has only that one side. The ramp and the floor share the two
vertices at the foot of the ramp. That shared edge is internal, and a body
crosses it without catching on the seam.

{{code ground}}

`createMesh` keeps the mesh in the world, and `setMesh` gives it to a fixed
body. One mesh can shape many bodies.

{{code mesh}}

## Step 2: A cylinder on the ramp

`NativeShape.cylinder(radius, halfHeight)` stands along its body's y axis.
Turned a quarter turn about x, it lies across the ramp and rolls down it.
Nothing in the core resists rolling, so on the level floor it would roll all
the way to the end. Damping its spin is a simple stand-in for rolling
resistance.

{{code cylinder}}

## Step 3: A cone

`NativeShape.cone(radius, height)` has its apex up along y. Its origin is its
centre of mass, which is a quarter of its height above its base, not
halfway.

{{code cone}}

## Step 4: A hull of six points

`createHull` takes the points and builds the convex hull around them. The
core weighs the hull as a solid and moves it so that its centre of mass is
the body's origin. `hullOffset` says by how much. Its corners are four
points round the middle and one above and one below, so its faces are easy
to write down: eight triangles from the top and the bottom to the edges of
the middle.

{{code rock}}

{{code hull}}

## Step 5: A rounded box

`setRounding` grows any shape by a ball of the given radius. A box of half
size 0.25 rounded by 0.08 has round edges and corners and is 0.33 from its
centre to each face. Rounding makes a box roll over its edges more smoothly
and rest on a face as before.

{{code rounded}}

## Step 6: Draw them as the core has them

Each body is drawn at its position and orientation. Two need care. The
cone's mesh has its middle at its origin, so it is held a quarter of its
height up inside a node at the body. The rock's mesh is its points less the
hull's offset, so that it turns about the same point as the body.

{{code draw}}

## Step 7: Where each one has to end

After ten seconds the cylinder has to be off the ramp and at least a metre
past its foot, lying on its side, its centre one radius above the floor.
The cone has to stand on its base with its centre a quarter of its height
up. The rock's lowest corner has to be on the floor. The rounded box has to
lie on a face, 0.33 up. Every height has to be within a centimetre. The
cone, the rock and the box also have to be asleep.

{{code check}}

> **Note.** Every shape here rests a few millimetres lower than its size
> says: the cylinder 5 mm, the cone 3 mm, the rock 6 mm. That is how far the
> contacts are allowed to overlap. The rounded box is drawn as a plain cube
> of its outer size, so its corners on screen are sharper than the ones it
> collides with. A mesh is one-sided, and only fixed bodies can be meshes.
> A moving body made of several shapes is a compound (`createCompound`).
