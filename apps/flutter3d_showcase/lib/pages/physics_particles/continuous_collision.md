# Fast bodies and thin walls

A body is stepped from where it is to where its speed takes it in one step.
At three hundred metres a second and sixty steps a second, that is five
metres, and a wall a centimetre thick is never anywhere the ball is. Without
something more, the ball goes through it.

The physics core has two answers. Soft continuous collision is on for every
new world: a contact reaches as far as its two bodies can close in a step, so
the solver sees the wall before the ball gets there. Hard continuous collision
is for a body you mark as a bullet: after the solve it is swept along the
path it took and put back where it first met something. This page fires
three balls at one thin wall, one with each answer and one with neither.

## Step 1: Two worlds, because speculative contacts are a world's

`speculative` is a setting of a `NativeWorld`, not of a body, and it is on
when the world is made. The green ball's lane lives in a world left that way.
The other two share a second world with it turned off, so the only thing
stopping the bullet is the sweep. Gravity is off in both, so the balls fly
level. If the core will not start, the reason is kept and the page draws the
wall with nothing to fire at it.

{{code worlds}}

## Step 2: A wall and a ball

Each wall is a fixed box a centimetre thick. Each ball is a dynamic sphere
ten centimetres across, three metres in front of it. `setBullet` is the whole
difference between the amber ball and the red one, which sit in the same
world. A bullet costs a sweep against every body after each step, so it is
meant for what is small and fast, not for everything.

{{code lanes}}

## Step 3: Fire, and step

Every second and a half all three balls go back to the line and leave at the
speed on the slider. Each frame steps both worlds by a sixtieth of a second.
A streak is drawn from the line to each ball, because at these speeds a ball
is in a frame for one step and then stopped or gone. Turn the speed down and
the red ball starts to stop at some speeds and pass at others: whether it
does depends on where its last step before the wall happens to end, which is
exactly the luck the other two do not rely on.

{{code fire}}

{{code step}}

## Step 4: What has to happen

From a fresh shot at three hundred metres a second, thirty steps later, the
green ball and the bullet have to be on the near side of the wall and the red
ball on the far side. On macOS the first two stop five and a half centimetres
short of the wall's middle, touching its face, and the red one is about
thirty metres past it, slowed by the air on the way.

{{code check}}

> **Note.** The soft kind stops what is coming straight at a wall, but it
> works from the speeds at the start of the step. A body that turns sharply,
> or is struck mid-step by something else fast, can still pass a contact it
> did not expect. The sweep follows a bullet's path through the step, turns
> included, but it is not run between two bullets, and a turn of more than
> half a revolution in one substep is past what it follows.
