# Particles that light

A fire is its particles, so the light it casts should come from measuring
them rather than from a second, hand-tuned glow running alongside. Mix
`LightEmitter` into whatever you pass as a burst's or a standing emission's
source, and the particle system fills in a `ParticleGlow` for you every step.

## Step 1: Something to be lit by

`LightEmitter` is a mixin with nothing in it beyond the `ParticleGlow` it
carries. A torch, a muzzle flash, anything whose particles should count as
light, mixes it in.

{{code emit}}

> **Note.** `count` on the effect only matters to a burst. A standing
> emission like this one spends its rate every sub-step and never reads
> `count` at all.

## Step 2: A light with nothing to say yet

The room needs an actual `LightNode` to be lit by, and it starts at zero
intensity: nothing is known about the flame before the first step has run.

{{code light}}

## Step 3: Keep the flame stepping

{{code advance}}

## Step 4: Let the light follow the fire

Every step, the torch's glow is asked how much it amounts to and where it is
centred, and the light is moved and dimmed or brightened to match. `located`
stays false until the first particle has actually been measured, which is
what keeps the light from sitting at the origin for the one frame before
anything is burning.

{{code follow}}

> **Warning.** A torch that goes out keeps casting light for a little while:
> the glow is smoothed, not read raw, so a strobe of one particle a frame
> does not read as one either.

## Step 5: What the page checks

A torch that has actually been burning for a step should have counted
particles and measured a positive amount of light.

{{code check}}

