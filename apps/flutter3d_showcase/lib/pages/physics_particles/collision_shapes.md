# Collision shapes

`CollisionShape` is sealed over five variants: a box, a sphere, a capsule, a
wedge and a heightfield. Every pair of them has a closed-form overlap test,
which is what lets a `CollisionWorld` answer a query without an iterative
solver that might not converge in the middle of a step.

## Step 1: Five shapes, one world

A box is level geometry. A sphere is a pickup or a projectile. A capsule is
anything that walks. A wedge is a ramp, and it is not a box: it tapers to an
edge at its low end rather than filling its own bounding box there, which is
the whole of what makes it walkable rather than a wall you can stand on top
of. A heightfield is ground, and the first shape here that is not one convex
solid: it hands a query the triangles near it instead of a single set of
planes.

{{code shapes}}

## Step 2: Ask the world, not the shapes

Nothing here compares two shapes directly. A `CollisionWorld` holds the
colliders and answers overlap, raycast and sweep queries against whichever
of them are near enough to matter. A small probe placed exactly at the
sphere's own centre should find the sphere.

{{code probe}}

## Step 3: What the query proves

The five shapes are spaced apart on purpose, so the probe above should find
the sphere and nothing beside it. That is the shape hierarchy actually doing
its job: five different pieces of maths, one shared answer.

{{code check}}

> **Note.** A wedge and a heightfield are not drawn from a generator this
> engine ships. The meshes on this page are built by hand, vertex by vertex,
> to match the numbers the collision shapes were given.
