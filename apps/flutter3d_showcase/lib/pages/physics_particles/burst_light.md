# A burst that lights the room

Before a burst could carry a light source, an explosion or a muzzle flash cast
no light however bright its particles were painted. `ParticleSystem.burst`
takes an optional `source`, and a `LightEmitter` passed there is fed by the
burst's own particles from the instant they appear.

## Step 1: One argument on an ordinary burst

Nothing about the burst itself is different: the same count, the same
emitter, the same lifetime a plain spark burst would use. The only new thing
is `source`.

{{code source}}

## Step 2: Follow it while it lasts

The glow fades on its own once the last particle of the burst has died, so
the light needs no cleanup: it is measured every step, for exactly as long as
there is anything left to measure.

{{code follow}}

## Step 3: What "lit" means here

A burst that never reaches a light emitter never updates a `ParticleGlow`,
so the check on this page is direct: after one step, the flash should have
counted particles and produced a positive amount of light.

{{code check}}

> **Note.** This is the same mechanism the standing-emission torch on the
> particle-lights page uses. The difference is only in how the particles
> arrive: all at once here, one sub-step's worth at a time there.
