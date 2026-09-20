# Bridging a falling rigid body and its collision

`RigidBodyComponent` bridges one `flutter3d_physics` `RigidBody` the same way
`Object3dComponent` bridges any other transform — the solver decides where
the body is, and the Flame side only ever reads it. `CollisionBridge`
re-fires flutter3d's own collision events as Flame's `CollisionCallbacks`.

## Step 1: A world and a body to fall through it

A static floor, a `Dynamics` solver, and a `RigidBody` dropped above it. A
thin trigger sits just above the floor too — `Dynamics` stops a falling body
exactly at the surface it lands on and never inside it, so the floor itself
never has an overlap to report; the trigger genuinely overlaps the crate the
moment it arrives, without affecting how or where `Dynamics` actually settles
it, since `Dynamics.step` ignores triggers entirely.

{{code world}}

{{code body}}

## Step 2: Bridge the body and its collisions

`RigidBodyComponent` wraps the body; `CollisionBridge` attaches itself to the
body's own collider and relays what it touches. The trigger has no Flame
component of its own, so a stand-in answers `resolveOther` for it — without
one, the bridge would have nothing to hand back and would call nothing at
all.

{{code bridge}}

## Step 3: Fall, land, and hear about it

Each `Dynamics` step moves the body; each `CollisionWorld.update` dispatches
whatever now overlaps.

{{code fall}}

The crate settled where the solver's own resting height says it should, and
on the way down `CollisionBridge` had already turned its overlap with the
landing trigger into a call on the Flame-side component — the same event a
native Flame body colliding with another would fire.
