---
description: Incompressible liquid in vessels of any shape, in SI units under the world's gravity and in its air. Waves from the vessel's own modes, weirs and orifices, streams that keep their continuity and break into drops, drops that fly as one body and hold to a wall, puddles, evaporation, laminar and turbulent flow, capillarity, pipes between vessels, layers that do not mix, and bodies that float.
---

# Liquids

The liquid part of `flutter3d_physics` lives in `lib/src/fluid/` and knows nothing about any particular game. It is in metres, kilograms and seconds, and gravity and air are whatever the world says, so the same tube on the Moon pours six times slower and its meniscus stands six times taller.

It is a hybrid, because no single method is right everywhere. Liquid standing in a vessel is a volume with a free surface on it, and the surface moves by its modes. Liquid leaving a vessel is a stream of parcels. A stream that breaks becomes drops, each one body in flight, and liquid on a wall is particles. What reaches a floor lies there as a puddle. Each part hands volume to the next one exactly, and the world can tell you where every cubic millimetre is, including what went to vapour.

```dart
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

final world = FluidWorld(
  gravity: Vector3(0, -9.81, 0),
  world: worldProperties,                 // its air: temperature, pressure, humidity, wind
  floor: [
    PlaneObstacle(
      normal: Vector3(0, 1, 0),
      offset: 0,
      surface: SolidSurface.benchTop,     // what the floor is made of
    ),
  ],
);
final tube = LiquidBody(
  shape: RevolvedVessel(tubeInside),     // any lathe profile, or a MeshVessel
  medium: FluidMedium.water,
  volume: 8e-6,                          // eight millilitres
  concentrations: {'dye': 1.0},
  wallThickness: 0.0005,
);
world.bodies.add(tube);

// Every frame: where the glass is, then the time that passed.
tube.place(rotation, position);
world.advance(dt);
```

Draw it with `liquidMeshes(tube)` from `flutter3d_effects`, and `jetMesh(jet)` and `particleMesh(...)` from `flutter3d_core`'s geometry. The chemistry bench is built this way; its [article](/education/chemlab/) shows what that looks like.

## Volume first

A vessel is a `VesselShape`: something that can say how much of it lies under a plane. `RevolvedVessel` does it exactly upright, as a sum of frustums, and tilted as a sum of circular segments. `MeshVessel` takes any closed mesh and does it with the divergence theorem over the triangles the plane cuts. Everything else is built on that one question. The surface's height is the plane that leaves the liquid's volume under it, and the most a tipped glass holds is the volume under its lowest point of rim.

So the volume is never derived from the surface. It is the number the liquid has, and the surface follows from it. That is how it stays conserved to rounding through any amount of tilting, and the tests hold it to a millionth.

## The surface

The surface is the plane level in the gravity the liquid feels: the world's, less the vessel's acceleration, which the body works out from where it was placed and when. Swing a glass and the plane swings with the felt gravity.

On that plane the liquid rocks. The waves are the modes of the surface in that particular vessel: the plane's cut through the vessel is laid out on a grid, and the lowest eigenvectors of its Laplacian, with no flow through the wall, are found by Lanczos iteration on the shifted inverse. Each mode is an oscillator at ω² = (gk + σk³/ρ)·tanh(kh), the dispersion relation of capillary-gravity waves in liquid of depth h, stepped exactly, not by Euler. For a cylinder that comes out within four percent of the Bessel-function answer on the default grid, and the tests check that it does. For a flask, or anything else, there is no closed form to check against, and the same code gives its modes.

The modes depend on the cells the cut takes and on nothing else, so they are solved once per cross-section and kept (`LiquidShapeCache`): a straight glass has one cross-section all the way up, and a rack of tubes shares one. The Laplacian is factored once as a band, its width a row of cells, and every Lanczos step is two sweeps along it.

Damping is the boundary layer at the wall, after Stephens and Dodge, which grows with the root of the frequency, plus 2νk² from the bulk. In glycerol, waves barely start.

A knock is a heap of liquid where it lands, projected onto the modes; the modes take it from there.

## Out over the edge

Where the surface stands above the rim, liquid leaves over it as over a sharp-crested weir, C_d·(2/3)·√(2g)·depth^(3/2) per metre of rim, with C_d = 0.62. It comes from the top layer and carries that layer's solutes. A hole in a wall is Torricelli's orifice with the same coefficient, and `pipeFlow` takes the lesser of Poiseuille's flow and the inertial limit.

## Streams

What leaves goes into a `Jet`, as parcels each holding one step's flow. A parcel's section is its volume over the distance it moves in a step. That is the continuity equation, and nothing enforces it separately: a falling stream thins as it speeds up because its parcels stretch.

- The sheet off a lip draws in at the Taylor–Culick speed, so it rolls up into a round thread.
- A thread grows Rayleigh–Plateau ripples at Weber's rate, the Grant–Middleman form of it, and breaks into drops when they have grown e¹² times. On a wall it does not break.
- Where it meets glass the liquid wets, it runs down the wall as a rivulet. Too slow, and it runs down the outside of the glass it came from: the teapot effect, with cling speed √(σ(1 + cos θ)/(ρe)).
- A fast drop that lands on a surface splashes when Mundo's K = Oh·Re^1.25 is over 57.7.

The world keeps the accounts: every jet's `emitted` is `inFlight + landed + dropped`.

## Drops

A drop in flight is one body. Falling, it does not feel its own weight, and what would break it up is the air: it holds together while its aerodynamic Weber number ρ_a·u²·d/σ is under about twelve (Pilch and Erdman), and a four-millimetre drop at a metre a second is at a fifteenth of that. So liquid under the capillary length is a `LiquidDrop` in `ParticleFluid.drops`: a sphere's drag and evaporation, and on a wall the hold of its edge or a slide. Drops that touch run together, with their momentum and what is dissolved in them. A drop wider than the capillary length that comes to a wall spreads there as particles, and particles that leave every wall gather into a drop again.

Liquid on a wall is `ParticleFluid`'s particles, position-based fluids. Particles are held to the rest density only where they are compressed, so a surface does not pull itself inward. Cohesion follows Akinci, with the coefficient worked out so that pulling a slab of particles apart costs 2σ per square metre, which is what surface tension is. A particle is stepped in substeps short against the capillary time √(ρs³/σ), a third of a millisecond for millimetre water, and short enough that nothing passes through glass between one look and the next. Drops and particles that land in a vessel become its liquid, with what was dissolved in them. Liquid arrives in any amount and is laid out as whole particles; what is short of one waits only while more is coming, and then goes as a droplet of its own where the rest came in.

## Wetting

A wall says what it is made of (`JetObstacle.surface`, a `SolidSurface`), and a liquid meets it at the angle the material catalogue gives for the pair, with that pair's hysteresis: the advancing angle less the receding one. Between the two the edge of a drop does not move, so it holds the drop with Furmidge's σ·w·(cos θr − cos θa) across the circle it wets. A microlitre hangs on a pane of glass while nine run down it. The catalogue has water on glass (about 20°, holding over 10°), on PTFE (about 110°) and on a phenolic bench top (about 75°, holding over 25°), each with its source; a liquid with no pair for a solid keeps its own angle and a hysteresis of about 10°.

## Puddles

A `PuddleSurface` in `FluidWorld.puddles` takes what lands on it as `Puddle`s, one body each with a volume and what is dissolved in it, not particles. Its angle is the surface's, so water beads on a phenolic bench and spreads on glass. A spread puddle is 2ℓc·sin(θ/2) deep, under a millimetre for water on glass; a smaller one is a spherical cap meeting the surface at its angle. It spreads there as a viscous gravity current, R ∝ (ρgV³/μ)^⅛·t^⅛ (Huppert), which water finishes in milliseconds and honey does not. Puddles that meet run together.

## Laminar and turbulent

Where it matters, the Reynolds number decides the law.

- In a `Pipe`, friction is Darcy's: 64/Re under 2300, Haaland's form of Colebrook over 4000 for the bore's `roughness`, and in between a straight line from one to the other, which claims no law it does not have. `Pipe.reynolds` says where a flow is. The column's solver holds it back by Poiseuille's friction with the viscosity scaled by f·Re/64, which is Darcy's loss, so the core and the Dart reference step it alike.
- A stream that leaves the lip under 2300 is smooth and parts by its own ripples. Past 4000 it leaves already disturbed and parts at Grant and Middleman's turbulent L/D = 8.51·We^0.32 (`Jet.intactLength`), a quarter of the laminar length for a brisk five-millimetre stream.
- Waves in a vessel are damped in the laminar boundary layer at the wall, which is what they have at a bench's sizes.

## Air

A `FluidWorld` has a `FluidAir`, the world's own: its temperature, pressure, humidity and wind from `WorldProperties`. Its density is moist air's as an ideal gas, unless the world says its air's density outright; its viscosity is Sutherland's, and water vapour diffuses through it at Marrero and Mason's rate.

- A drop falls against the engine's sphere drag at its own size, so a millimetre drop settles at about 3.5 m/s. Gunn and Kinzer measured 4.03: a drop's inside circulates, and a rigid sphere's drag does not know that.
- A stream bends in a crosswind, with White's drag on a cylinder across it.
- Open liquid evaporates. A tube does so up the air standing over its liquid and out of its mouth, Stefan's tube, a few microlitres an hour. A puddle follows Hu and Larson in still air and a flat plate's boundary layer in a wind, and a drop follows Ranz and Marshall. Only the solvent leaves, so what is dissolved grows stronger, and `FluidWorld.evaporated` keeps the vapour in the accounts.

Only water has a vapour curve so far; the other media do not evaporate yet.

## Gravity that varies

`FluidWorld.gravity` is one vector for everything. Give the world a `GravityField` instead and each vessel, drop and parcel of a stream feels the gravity where it is. `AttractorGravity` is a uniform part and any number of `Attractor`s, each pulling as μ·r̂/r² and inside its radius as a uniform ball does. `SampledGravity` reads a field of `f3d.gravity` of the shared field contract, three values a cell, which `AttractorGravity.writeField` writes and anything else that keeps fields can too. A glass beside an attractor levels across its own pull.

## Capillarity

`TubeMeniscus` solves the Young–Laplace equation for a tube's radius and the liquid's contact angle by shooting, its curvature found by Illinois false position, so a narrow tube's meniscus is the right curve, not a fillet. `jurinHeight` is the rise in a thin tube, and the tests check one against the other. A `LiquidBody` lifts its drawn surface by the meniscus and adds the capillary pressure where it matters, in pipes. A meniscus depends on the liquid, the radius and gravity alone, and is solved once for every vessel that needs it.

## Off the frame

A cross-section not met before, or a meniscus, is a few milliseconds of solving. Where they are worked out is `FluidWorld.shapes`, a `LiquidShapeSolver`: at once by default. `BackgroundShapeSolver` from `flutter3d_physics_native` sends them to a long-lived isolate instead and keeps the answers where every vessel finds them; until an answer comes, a surface rings on the grid it had and a vessel goes without its meniscus. The answers are the same numbers, only later, so a world under a bit-exact profile refuses it. In the browser it works at once.

## The pair loops as kernels

The particles' loops over pairs of neighbours (density, the colour field, cohesion and curvature, the density constraint and its correction, XSPH) are also written once in the [kernel language](https://github.com/pleiondev/flutter3d/blob/main/docs/kernels.md), over flat buffers and compressed neighbour rows: `liquidPairKernels` and `KernelLiquid` in `flutter3d_physics_native`, a `FluidSolver` whose walls, moves and neighbour rows stay on the host. Where the loops run is the hardware layer's to say (`placeKernelLiquid` in `flutter3d_effects`): under a bit-exact profile on the CPU kernel, the same bytes on every machine. Where the run need not replay, a native executor takes them instead (the hardware layer's `ComputePlacement.nativeSimd`, which any work with lanes of its own can use), the same loops in C on the processor's AVX2, AVX-512 or NEON lanes, held to the CPU kernel within a part in ten thousand of a spacing a substep (`KernelLiquid.nativeTolerance`) and refused under a bit-exact profile.

## Pipes between vessels

A `Pipe` joins two bodies at given points. The column in it has inertia, so two vessels joined by a long pipe swing towards the same level and overshoot, as a U-tube does, and friction is Darcy's for the flow's Reynolds number plus minor losses. Pressure at each end counts every layer above it and the capillary pressure, so a narrow tube joined to a wide one stands higher by the difference of their capillary rises, not at the same height.

## Layers

A body holds layers. Liquids that mix are one layer, keeping amounts of solutes, so pouring adds them. Liquids that do not mix lie in separate layers by density, oil on water, and each has its own top. `layerTops` gives them and `pressureAt` sums them.

## Floating things

`FloatingBody` wraps a rigid body. The liquid pushes up with ρgV of what it displaces, exactly for spheres, boxes and capsules, and drags with White's coefficient for the part that is under. The displaced volume raises the level. A small ball sinking in glycerol settles at Stokes's speed; the tests check it within three percent.

A body turning in the liquid is held back too, by Stokes's torque 8πμR³ω on the sphere of its volume, for the part of it that is under: a ball spun in glycerol slows by e in ρR²/15μ.

## Being honest about it

- The surface is linear, so it rocks harder where real water would break.
- Streams and drops collide with revolved vessels and planes; a `MeshVessel` holds liquid but does not yet stop a stream.
- Particles are on the CPU, so dozens are cheap and thousands are not. The drops in flight cost almost nothing.
- Everything that is stepped uses `Portable` maths, so the same inputs give the same bits on every platform; the air, the drops, the walls' hold and the puddles are plain Dart and the same on every backend.
