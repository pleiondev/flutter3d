# A Catmull-Rom path

A cubic spline is naturally parameterised by a number that runs one unit a
segment, and that number moves at a different speed everywhere along the
curve. `CatmullRom` measures the curve once when it is built and takes
distance in metres everywhere after that, which is what anything driving
along a track actually wants.

## Step 1: Build a closed loop

Four points, a little over a metre from the centre, joined into a loop.

{{code track}}

## Step 2: Sample it by distance

`sampleAt` writes the point a given distance along the curve into a vector.
`wrap` brings a distance back into range, looping past the end of a closed
curve instead of clamping.

{{code sample}}

The car on this page advances two metres a second along the loop, wrapping
back to the start once it has gone all the way round.

## Step 3: Check it closes

{{code measure}}

Sampling at zero and at the curve's own length gives the same point, because
a closed curve is exactly that: one loop, with no seam to fall off of.
