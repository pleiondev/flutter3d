# The physics core

Rigid bodies, cloth and liquids can be stepped by two backends. The Dart
reference is `flutter3d_physics` itself: plain Dart, on every platform, from
the first line. The core is `flutter3d_physics_native`, the same physics written
in C, built by the package's hook for each target and loaded as WebAssembly in
the browser. A game asks once, at the start of the run, and every world after
that is made on the answer. The core is the default; the reference is what a
run falls back to when the core will not start.

This page drops the same six crates twice. The left pile is on the reference
and the right pile on the core, so you can watch the two agree.

## Step 1: Ask for the core, and keep the reason when there is none

A game calls `startPhysics()` in its `main` and `usePhysics()` everywhere
after, which makes one choice for the whole run. This page needs both backends
at once, so it builds them itself and leaves the run's choice alone.

`NativePhysics` is the core as a `PhysicsBackend`, and `DartPhysics` is the
reference. Starting the core is tested, not assumed: a world is made and freed
straight away, which is the first call that would find a missing library or
bindings for another ABI. If that throws, the right pile goes to the reference
too, and the switch beside the viewport says why. In the browser the core has
to be fetched first, so a page opened before anything loaded it says that
instead.

{{code backends}}

## Step 2: One drop, built the same way twice

Both piles are built by one function from the same numbers: a floor, and six
crates nearly in a column, each a little higher than the last. The backend is
the only argument. `dynamics(world)` is where it matters, and it answers a
`RigidDynamics`, the interface that `Dynamics` and the core's `NativeDynamics`
both implement. The crates are the same `RigidBody` objects on either side,
with their colliders in an ordinary `CollisionWorld`, so the rest of a game
never needs to know which backend stepped them.

{{code drop}}

## Step 3: Step both

One step of each a frame, at a sixtieth of a second. The left pile is on
the left floor and the right pile on the green one. Every six seconds both
are dropped again. Switch **Right pile on the core** off and both sides are
the reference, moving as one.

{{code step}}

## Step 4: What the two should agree on

Left for four hundred steps, every crate on both sides has to end on the
floor or on another crate, and asleep. The right pile has to really be on
the core wherever the core started. The two towers have to end within three
centimetres of each other, crate by crate. On macOS they come within one and a
half.

{{code check}}

> **Note.** The core is not the reference to the bit. It steps in single
> precision with its own contact solver, so a run's digests differ between the
> two, though the core gives the same bits on every platform. A tower like this
> one settles to almost the same place either way. A crate that lands on the
> edge of another can fall off on one side and stay on the other: dropped
> further apart, these same six crates end up more than a metre apart. A replay
> therefore records which backend it ran on, and plays back on that one.
