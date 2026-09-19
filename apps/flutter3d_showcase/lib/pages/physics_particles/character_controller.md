# A character controller

A rigid body that never rotates and never bounces is the wrong tool for a
player: what a player wants is to slide along a wall rather than bounce off
it, and to feel the same on every machine regardless of frame rate.
`CharacterController` is a second, purpose-built way of moving a body
through the same `CollisionWorld`.

## Step 1: Something to stand on

{{code floor}}

## Step 2: The walker itself

A controller registers its own collider in the world it is given, so a
monster sees the player as an obstacle and a trigger sees them arrive. Left
unspecified, the shape is a box; a capsule suits anything a melee swing or a
blast needs to test against exactly.

{{code controller}}

## Step 3: Step it, more than once

`step` takes a wish direction and the seconds since the last call. It
already applies gravity, tries to jump if one was buffered, moves the body
and slides it along whatever it meets, and probes the ground underneath it,
all in one call. A page rendered once cannot wait for real frames, so it
runs the steps a game would spread across a second and a half up front,
before the one frame it draws.

{{code walk}}

## Step 4: What landing means

`isGrounded` is true once the probe below the feet finds something to stand
on, and `groundNormal` is the face it found: straight up on a flat floor,
tilted on a slope. Reading it costs nothing extra — the probe already knew
it and used to throw it away.

{{code check}}

> **Note.** `groundBody` is null here, because the floor is a static box and
> nothing is carrying the walker. It is only ever set to something that
> moves under its own power, such as a lift.
