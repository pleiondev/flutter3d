# Frame timing and memory pressure

Three small instruments an application reaches for once it is running for
real: how long the last frame actually took, what a window of frames cost on
average and at their worst, and giving memory back when the platform says it
is short of it.

## Step 1: The frame clock

`FrameClock.tick` measures the wall between calls. The very first tick
answers nought rather than a guessed sixtieth of a second, because nothing
has actually been measured yet.

{{code clock}}

## Step 2: A window of frame costs

`FrameTimingLog.note` takes a build duration and a raster duration and
returns a summary line once its window of frames is full, and null on every
frame before that.

{{code timing}}

## Step 3: Give memory back

`MemoryPressureRelease` calls `Renderer.releaseTransientTargets` when the
platform warns about memory. Pooled render targets otherwise settle at a
high-water mark and stay there for the rest of the session.

{{code pressure}}
