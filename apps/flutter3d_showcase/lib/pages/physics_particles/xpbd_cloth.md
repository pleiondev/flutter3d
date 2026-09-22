# Cloth

A `ClothMesh` is a grid of particles and the constraints between them: edges
that resist stretching, and cross-edge pairs that resist folding.
`stepCloth` advances it with an XPBD solver, which is what stays stable at a
compliance of zero without a spring constant that has to be retuned every
time the substep count changes.

## Step 1: A sheet, and something in its way

`ClothMesh.grid` pins the top row so the rest has something to hang from
rather than falling forever. A `ClothObstacle` is a `CollisionShape` and a
position, the same shapes the rest of this package's pages use, tested
through `expandedPlanes` rather than through anything cloth-specific.

{{code cloth}}

## Step 2: Step it every frame

Each call divides `dt` into `ClothSettings.substeps` XPBD substeps: gravity
and damping predict a new position, the structural and bending constraints
are solved against that prediction, and particles are pushed back outside
every obstacle before the result is folded into velocity and position. Here
it runs live, a step a frame: the sheet falls into place from lying flat, and
then a ball swings through it and a gust of wind, which `WindSettings` applies
per triangle as drag along its own normal, rises and falls. **Wind** sets how
hard the gust blows; **Swing the ball** stops the ball where it is.

{{code live}}

## Step 3: What the sheet should do

The pinned row never moves, because its inverse mass is zero and nothing an
XPBD constraint does can reach a particle with no mass to correct. Left alone,
the free edge should hang well below where it started, and a ball pushed into
the sheet should never end up with a particle inside it.

{{code check}}

> **Note.** This package has no scene graph of its own. The mesh on this
> page is rebuilt from `ClothMesh.positions` and `ClothMesh.triangles` every
> frame, with a normal at each particle worked out from the triangles that
> meet there, the same way the heightfield page draws its own terrain from a
> `Float32List` of samples.
