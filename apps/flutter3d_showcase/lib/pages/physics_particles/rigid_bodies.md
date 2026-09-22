# Rigid bodies

Stage one of two: mass, gravity, impulses, being pushed, and coming to rest.
A rigid body here has no rotation and no inertia tensor, which is what makes
contact between two boxes exact and cheap rather than a search over a
manifold. Which is why the crates on this page slide and stack but never
tumble.

## Step 1: A world with something to fall onto

`Dynamics` is the solver; `CollisionWorld` is still what everything, moving
or not, lives in.

{{code world}}

## Step 2: Bodies above the floor

A rigid body's collider is added for you, the same as a character
controller's. From the collision world's point of view the only questions
are whether it moves and whether it blocks, and the answer to both is yes.
The crates are dropped from different heights so they land one after another.

{{code body}}

## Step 3: Step it every frame

One `step` a frame, at a fixed sixtieth of a second: the same drop lands the
same way on every machine, which is what makes the snapshot below worth
having.

{{code live}}

## Step 4: A snapshot before anything moves

`save` is everything a body needs to be put back exactly where it was:
position, velocity, and whether it had fallen asleep. It carries no
reference to the world or the collider, so it can sit in a save file.

{{code snapshot}}

## Step 5: Disturb the pile, then undo it

**Shove them** gives every crate an impulse, which wakes the ones that had
gone to sleep. When the pile has been at rest for a moment, or **Rewind to
the start** is pressed, `restore` puts every crate back where the snapshot
says and the drop begins again.

{{code shove}}

{{code restore}}

## Step 6: What the pile should prove

Left alone, every crate has to end up on the floor or on another crate, and
asleep. Restoring the snapshot has to put each one back exactly where it was
saved.

{{code check}}

> **Note.** A sleeping body costs nothing to leave alone: the solver skips
> it entirely until something touching it moves fast enough to be worth
> waking it for. Ten crates settled in a stack are ten bodies the physics
> stops paying for.
