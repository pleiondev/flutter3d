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

## Step 4: Draw the curves

The page plots all three against distance, thirty metres wide. Slide **Distance**
and the marker sweeps along them, each curve's dot reading off what that curve
answers there. The inverse curve drops fast and then lingers; the linear one
falls in a straight line to nothing at its maximum; the exponential one sits
between them. The same `gainAt` call draws the whole plot, for the same three curves as before.

{{code curves}}
