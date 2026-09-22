# A particle pool in one draw call

A game does not want a hundred sparks to cost a hundred draw calls. This
engine keeps every live particle in one pool and draws the whole pool in a
single instanced call, whatever effect put each particle there.

## Step 1: A pool with a seed

`ParticleSystem` owns a fixed number of particle slots, reused for the life of
the application. Passing a seed makes the whole simulation reproducible: the
same seed and the same sequence of calls give byte-identical particles, which
is what lets the check at the end of this page count on an exact number
rather than a range.

{{code system}}

## Step 2: A recipe, not an object

A `ParticleEffect` is data: how many particles a burst makes, where they
start (an emitter), how long they live, how big they are, and what colour.
Nothing here is a specific effect. An explosion and a puff of dust are the
same four fields with different numbers.

{{code effect}}

## Step 3: One burst, one contributor

`burst` fills as many slots as the effect asks for, all at once.
`ParticleContributor` is what actually draws them: it reads every live
particle out of the pool and writes one batch of camera-facing quads, so the
system can hold a thousand particles from a dozen different effects and still
cost one draw.

{{code burst}}

## Step 4: Keep it moving

A particle system does nothing by itself. Every frame, `advance` steps the
simulation forward: it ages each particle, applies whatever affectors it
carries, and moves it by its velocity.

{{code advance}}

> **Note.** `advance` divides its input into fixed sub-steps of a
> hundred-and-twentieth of a second, so the same effect looks the same
> whether the frame is running at thirty hertz or a hundred and twenty.

## Step 5: What the page checks

The seed from step one is what makes this an exact number rather than a
guess: the same burst always emits the same count, so the check is that the
pool still holds exactly that many, and that the contributor actually drew.

{{code check}}

