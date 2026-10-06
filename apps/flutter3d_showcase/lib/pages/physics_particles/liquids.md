# Liquids on the core

`flutter3d_physics` keeps liquids as a `FluidWorld`: vessels with a surface
that sloshes, pipes between them, the stream that runs over a lip, the drops
it breaks into, and rigid bodies floating in it. What is where, and how much,
is kept in Dart either way. The parts stepped through time (the surface's
waves, a stream's parcels in the air, spilt particles, the column in a pipe
and the push on a floating body) go to a `FluidSolver`. On the physics core
that is `NativeLiquid`, the same arithmetic in C. The chemistry bench uses
exactly these pieces for its glassware.

This page shows three of them on one bench: a U-tube that levels out, a
floating block, and a pour from one test tube into another.

## Step 1: The core's solver, or the reference's

A game calls `startPhysics()` once, and every `FluidWorld` made after that
without a solver takes the run's, `usePhysics().fluid`. This page passes one
itself so the switch beside the viewport can turn the core off: `NativeLiquid`
where a core world can be made, `DartFluid` where it cannot, with the reason
kept to show.

{{code solver}}

## Step 2: Two tubes and a pipe

Two tubes four centimetres across, one filled to twelve centimetres and one
to six, joined at their floors by a pipe three centimetres long with a bore of
eight millimetres. The water in the pipe has mass, so the difference in
pressure accelerates it rather than moving it at once, and friction in the
pipe and at its ends slows it down. The levels overshoot by a couple of
millimetres, swing back and are level in about two seconds.

{{code utube}}

## Step 3: A block that floats

A basin twenty centimetres across with six of water, and a block of pine let
go a centimetre above it. The block is an ordinary `RigidBody` stepped by a
`Dynamics`; `float` hands it to the fluid world, which each step lifts it by
the weight of the water it displaces, drags it as it moves through the water,
and raises the basin's level by the volume it takes up.

{{code float}}

## Step 4: A pour

A narrow tube seven tenths full is tipped over a wider empty one. What runs
over its lip becomes a stream the world flies, parcel by parcel. What the
wide tube catches is added to its liquid, and what misses lands on the bench
as particles. The stream needs a finer step than the vessels, so the pour has
a world of its own at a two hundred and fortieth of a second.

{{code pour}}

## Step 5: Step them

Each world runs on by whole steps of its own. Every vessel is placed before
each step with the time it is there at, because a vessel's acceleration is
read from its path. The block's `Dynamics` steps with the vessels' world, so
it falls once for every push it gets.

{{code step}}

## Step 6: What has to happen

After two and a half seconds the two tubes have to be level within three
millimetres; on macOS they are within one. The block is still bobbing then,
so what is checked is the share of it under water, averaged over the last
second and a quarter. At rest the water it displaces weighs what it does, so
that share is its density over water's, 0.6. It has to come within 0.05, and
comes to 0.61. The pour has to have reached the wide tube, with every drop
accounted for: the two tubes, the air and the bench together hold what the
narrow tube held to start with.

{{code check}}

> **Note.** The core is not the reference to the bit. It works in single
> precision and sums in another order, so a U-tube on it swings within a
> fiftieth of a millimetre of the reference's and a floating body stays within
> a tenth of one, but a splash goes its own way. Only the stepping moves to
> the core: the floating block here is still stepped by the Dart `Dynamics`,
> and a wall the core has no record for, a caller's own obstacle, sends that
> step back to the reference. The liquid in the tipped tube is drawn as a
> column along its axis, which shows it emptying but is not where the water
> lies.
