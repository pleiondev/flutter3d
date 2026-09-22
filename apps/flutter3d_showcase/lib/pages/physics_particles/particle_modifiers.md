# Forces

An emitter decides where a particle starts. Everything that happens to it
afterwards is a stack of small, independent affectors, run in order, once a
step.

## Step 1: A stack of small rules

Each affector does one thing. `ParticleGravity` pulls particles down.
`ParticleDrag` bleeds off speed exponentially, so a burst slows into a drift
instead of flying away forever. `ParticleWind` pushes everything one way.
`ParticleTurbulence` swirls particles through a standing flow field, which is
what makes smoke curl instead of rising in a straight line. `ParticleSpin`
turns a billboard over its life.

{{code affectors}}

## Step 2: Attach them to an effect

The list goes on the effect, in the order it should run. Nothing about the
emitter changes: this is the same cone shape from the emitters page, with
five things now happening to whatever it throws.

{{code effect}}

## Step 3: Burst it, and keep it moving

A burst is a single instant; the affectors above only do anything once the
system is advanced.

{{code burst}}

{{code advance}}

## Step 4: What changed

Gravity and drag together mean a particle thrown upward stops climbing as
fast as it started, and spin means it is turning by the time you look at it.
Neither is visible from the pool's own numbers, so the check on this page
runs the same affector list against a particle of its own and reads what
came out the other side.

{{code check}}

> **Note.** Affectors are stateless and shared between every particle that
> uses them. `ParticleSpin` reads each particle's own seed for its starting
> angle, which is what stops a whole burst turning in lockstep like a sheet
> of aligned squares.
