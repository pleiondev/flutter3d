# Navigation meshes and crowds

A grid tells an agent which cells it can stand in. A navigation mesh does the
same job with convex polygons: fewer of them, any shape, and stacked where a
walkway crosses over a floor. `NavMesh.bake` makes one from a level's brushes,
a route over it is a short list of corners, and `Avoidance` keeps bodies
walking those routes from walking into each other.

This page has a floor with a wall across its left half and a ledge in one
corner. The yellow ball walks the route round the wall, the orange line climbs
onto the ledge by a jump, and on the right eight bodies swap places across a
circle. The green lines are the mesh's polygons.

## Step 1: A level

Brushes are boxes, and the mesh is made from them, not from the collision
world. The collision world has doors in it, and a mesh baked with a door shut
has a wall where the door is. The wall is three brushes so that its middle can
be broken later. The ledge is 0.9 m up, too high to step onto.

{{code level}}

## Step 2: Bake

The bake voxelises the brushes, keeps the floors a body of the config's
height and radius fits on and can step between, erodes them by the radius,
cuts them into regions and outlines, and cuts the outlines into convex
polygons that know their neighbours. Everything from the voxeliser on is in
whole numbers, so `NavMesh.digest` is the same on every platform.

`tileSize` cuts the lattice into tiles of sixteen cells, and a region never
crosses a tile's edge. That is what step 5 needs. A tiled mesh has to keep
`maxEdgeError` under half a cell, and the config refuses one that does not.

{{code bake}}

## Step 3: A route round the wall

`route` runs A* over the polygons, entering each at the middle of the edge it
came through, and then pulls a string through the shared edges, the funnel.
What comes back is the start, each corner the string bends round, and the end.
Inside the corridor every polygon is convex, so walking straight from corner to
corner stays on the mesh. Costs are counted in whole millimetres and ties go
by the mesh's own order, so two machines find the same route. A goal nobody can
reach gives a route marked incomplete, ending at the nearest point there is.

{{code route}}

## Step 4: Jumps

Baked with a `JumpReach`, the mesh also looks for gaps, ledges and drops a
body with that reach can jump, and keeps the shortest link between each pair
of polygons. A route given the reach may take those links, and `jumps` says
which legs are flights. Without a reach the same route ends at the foot of the
ledge, incomplete. Bake with the most capable body a level has, and let each
route filter by its own.

{{code jumps}}

## Step 5: Break the wall and bake its tiles again

Switch on **Break the wall**. The middle brush is gone, and `rebake` bakes
again only the tiles its box reaches, widened by the erosion. It outlines the
ring of tiles round them again and cuts the polygons again from every outline.
The result is, digest for digest, the changed level baked whole on the same
lattice, in a fraction of the time on a real level. The route now goes
straight through.

{{code hole}}

## Step 6: A crowd

`Avoidance` is ORCA. Each neighbour rules out the velocities that would meet
it within the time horizon, each body takes half of the turning, and the
velocity picked is the one nearest the wanted one that every neighbour allows.
Every body picks from where all of them were before any of them moves, and
nothing is kept between steps. In a game, `ActorSystem.avoidance` does this for
every actor on the ground, after its route has said where it wants to go.

{{code avoid}}

## Step 7: What has to hold

The route has to be complete, pass the wall's end and be longer than the
straight line. The broken wall baked tile by tile has to have the same digest
as the broken level baked whole, and the route through it has to be a straight
line. The ledge has to be reached by a jump and not on foot. Eight bodies
crossing for ten seconds must never come closer than two radii, give or take a
centimetre.

{{code check}}

> **Note.** A mesh baked with jumps, or with small islands dropped, is not
> baked again by tiles: `rebake` refuses it and it is baked whole. Avoidance
> knows nothing of walls. The route keeps a body off them and the character
> controller slides it along them, which is why the crowd here stands on open
> floor and walks straight. A crowd stepped by exact velocities, as here, keeps
> its distance; actors moved by a character controller keep about 94% of two
> radii, since the controller only approaches the velocity it is given. A goal
> nobody can reach searches the whole of the start's part of the mesh before
> giving up.
