# Adaptive resolution

Every other setting on this page's neighbours trades a look for time: turn an
effect off and the frame gets cheaper. Resolution is the lever left once
everything else already is off and the frame still will not fit its budget.
`RenderSettings.renderScale` draws everything smaller, and `AdaptiveScale`
decides the number for you from how long frames have been taking.

## Step 1: Keep a scale that remembers

`AdaptiveScale` holds a window of recent frame costs and a scale it has
settled on. It is a plain object with no engine behind it: you own it, you
feed it, you read it back.

{{code adaptive}}

## Step 2: Feed it what a frame cost

Each call to `recordFrame` takes a cost in microseconds and returns the scale
to use for the next frame. This page has no real GPU work to measure, so it
feeds a simulated cost instead, in place of a real `FrameResult.cpuMicros`.

{{code record}}

Drag Simulated frame cost above the frame budget and the scale drops on the
very next tick, because this page's window is a single frame. A real game
should use a wider window: judging a frame slow from one sample chases noise
rather than a trend.

## Step 3: Apply the scale

Whatever `recordFrame` answered goes straight into the setting it exists for.

{{code scale}}

## Step 4: Confirm the frame actually shrank

`FrameResult.frame` is the texture the renderer drew, at the size it was
actually drawn at rather than the size that was asked for. Both axes shrink
together, so the saving is the square of the scale.

{{code size}}
