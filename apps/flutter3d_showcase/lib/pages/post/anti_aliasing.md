# FXAA and sharpen

Multisampling is the better way to smooth an edge, but it is a property of the
scene pass's attachments, and some effects switch it off for the whole frame.
FXAA is the other way: one pass over the finished picture that looks for hard
contrast steps and softens them, at the cost of never seeing an edge finer than
a pixel.

## Step 1: A staircase to smooth

A flat card turned off the axes draws every one of its edges as a diagonal,
which staircases badly with nothing else on.

{{code card}}

## Step 2: Turn it on

`AntiAliasSettings.enabled` runs the pass. `sharpen` rides in the same pass,
because the four neighbour pixels it needs are the same four FXAA already
reads: it is contrast-adaptive, so it pushes harder where the picture has
headroom and leaves an already-bright or already-dark pixel alone.

{{code settings}}

Turn FXAA off and the edges of the card turn to stairs. Turn it back on and
they soften. Raise Sharpen and the card's edge gets a little crisper again
without the staircase coming back, because sharpening runs after the
smoothing.

## Step 3: Read what the frame says

`FrameResult.antiAliasing.fxaa` says whether the pass actually ran this frame.

{{code reported}}
