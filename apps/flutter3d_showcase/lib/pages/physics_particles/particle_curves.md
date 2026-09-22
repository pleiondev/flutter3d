# Over-life curves

`ParticleSizeOverLife` only ever goes from one number to another, and
`ParticleFade` only ever goes down. A puff of smoke that grows and then
shrinks needs both shapes on the same value, which is what a curve is for: a
value described as a handful of keys, sampled wherever a particle's life
happens to be.

## Step 1: A curve for size

Each `CurveKey` sits at a point in `[0, 1]` of the particle's life. Between
two keys the value is eased by whichever shape the earlier key names, and
outside the first and last key the curve holds still rather than
extrapolating.

{{code curve}}

## Step 2: A gradient for colour

A `ParticleGradient` is the same idea for a colour: `GradientKey`s instead of
numbers, sampled the same way. Four independent channel curves would let the
keys drift apart and produce a grey frame nobody asked for; a gradient's keys
are keys of the whole colour at once.

{{code gradient}}

## Step 3: Read by an affector

A curve and a gradient are values, not affectors. `ParticleSizeCurve` and
`ParticleColorGradient` are the small pieces that read them every step and
write the result onto the particle, the same shape every other affector on
the modifiers page takes.

{{code effect}}

## Step 4: What the shape actually is

Neither a curve nor a gradient needs a running particle to check: they are
plain data, sampled directly. This page's own check does exactly that, off
the same two objects the burst above draws with.

{{code check}}

> **Note.** `KeyEase.smooth` eases into and out of a key rather than turning
> a straight corner there, which is what keeps a size that puffs up and back
> down from looking like it hit a wall in the middle.
