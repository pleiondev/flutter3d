# Rigid bodies

Stage one of two: mass, gravity, impulses, being pushed, and coming to rest.
A rigid body here has no rotation and no inertia tensor, which is what makes
contact between two boxes exact and cheap rather than a search over a
manifold.

## Step 1: A world with something to fall onto

`Dynamics` is the solver; `CollisionWorld` is still what everything, moving
or not, lives in.

{{code world}}

## Step 2: A body above the floor

A rigid body's collider is added for you, the same as a character
controller's. From the collision world's point of view the only questions
are whether it moves and whether it blocks, and the answer to both is yes.

{{code body}}

## Step 3: Step it until it lands

{{code fall}}

## Step 4: A snapshot of the moment it settled

`save` is everything a body needs to be put back exactly where it was:
position, velocity, and whether it had fallen asleep. It carries no
reference to the world or the collider, so it can sit in a save file.

{{code snapshot}}

## Step 5: Disturb it, then undo the disturbance

{{code perturb}}

{{code restore}}

## Step 6: What a round trip should prove

The crate should have settled at rest on the floor, and restoring the
snapshot should put it back exactly where it was saved, velocity included.

{{code check}}

> **Note.** A sleeping body costs nothing to leave alone: the solver skips
> it entirely until something touching it moves fast enough to be worth
> waking it for. Ten crates settled in a stack are ten bodies the physics
> stops paying for.
