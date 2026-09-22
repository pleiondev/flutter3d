# FXAA and sharpen

Multisampling is the better way to smooth an edge, but it is a property of the
scene pass's attachments, and some effects switch it off for the whole frame.
FXAA is the other way: one pass over the finished picture that looks for hard
contrast steps and softens them, at the cost of never seeing an edge finer than
a pixel.

## Step 1: A dozen staircases to smooth

One diagonal edge staircases too, but a single contrast step is barely enough
to see the pass do anything: FXAA looks like noise until there is more than
one edge on screen to compare. A dozen thin spokes crossing one centre put
every angle a staircase can take in the same handful of pixels at once,
which is where softening one of them into the others actually reads as
something.

{{code card}}

## Step 2: Turn it on

`AntiAliasSettings.enabled` runs the pass. `sharpen` rides in the same pass,
because the four neighbour pixels it needs are the same four FXAA already
reads: it is contrast-adaptive, so it pushes harder where the picture has
headroom and leaves an already-bright or already-dark pixel alone.

{{code settings}}

Turn FXAA off and the spokes turn to stairs, worst near the centre where
the most of them cross the fewest pixels. Turn it back on and that cluster
softens to grey. Raise Sharpen and the spokes get a little crisper again
without the staircase coming back, because sharpening runs after the
smoothing.

## Step 3: Read what the frame says

`FrameResult.antiAliasing.fxaa` says whether the pass actually ran this frame.

{{code reported}}
