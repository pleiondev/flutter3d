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

## Step 2: Step it until it settles

Each call divides `dt` into `ClothSettings.substeps` XPBD substeps: gravity
and damping predict a new position, the structural and bending constraints
are solved against that prediction, and particles are pushed back outside
every obstacle before the result is folded into velocity and position. A
page rendered once has to run all of that up front.

{{code settle}}

## Step 3: What settling should look like

The pinned row never moves, because its inverse mass is zero and nothing an
XPBD constraint does can reach a particle with no mass to correct. The free
edge should have sagged well below where it started, and nothing should
have ended up inside the ball it was draped around.

{{code check}}

> **Note.** This package has no scene graph of its own. The mesh on this
> page is rebuilt from `ClothMesh.positions` and `ClothMesh.triangles` after
> the sheet has settled, the same way the heightfield page draws its own
> terrain from a `Float32List` of samples.
