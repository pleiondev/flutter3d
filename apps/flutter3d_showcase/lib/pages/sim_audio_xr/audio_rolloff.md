# Distance rolloff

`Attenuation` is how a sound gets quieter with distance, and it is a
hierarchy rather than a single formula: a footstep and a siren do not fade
the same way, and a game can write its own curve alongside the three built
in ones.

## Step 1: Three curves

`InverseRolloff` falls off as one over distance, which is closest to how
sound actually behaves. `LinearRolloff` runs straight from full to silent.
`ExponentialRolloff` is steep near the source and trails off slowly after.

{{code curves}}

## Step 2: Sample each one

Every curve answers `gainAt` the same way: a number from 0 to 1 at a given
distance.

{{code sample}}

## Step 3: Check the shape

{{code compare}}

Every curve gets quieter as distance grows, and none of them has anything
left to say beyond its own `maximum`.
