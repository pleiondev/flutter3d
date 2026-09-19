# Several views in one frame

A `RenderView` is one camera drawing into one rectangle of the target, filtered
to the nodes whose `layerMask` it shares. A single render call can take more
than one of them, and every view lands in the same picture.

## Step 1: Put two meshes on two layers

The left cube's `layerMask` is 1, the right cube's is 2. A `SceneNode` starts
on layer 1 by default, so most scenes never need to think about this at all.

{{code layers}}

## Step 2: Crop the main view to a rectangle

`ViewportRect` is a fraction of the target, not a pixel size, so it survives a
resize unchanged. Here the visible view is cropped to the left half and given
layer 1, so only the left cube can appear in it. The right half stays the
clear colour, because nothing asked to draw there in this view.

{{code rect}}

## Step 3: Combine two views in one render call

This is the part a single visible viewport cannot show by itself: two
`RenderView`s, the same camera, opposite halves of the target and opposite
layer masks, passed to one `Renderer.render` call together. Both draw in the
same frame. The showcase's own viewport still shows the cropped single view
from step 2; this second call renders into its own frame so the two can be
compared.

{{code split}}

## Step 4: Switch which layer the visible view shows

The toggle changes which cube the cropped, single-layer view can draw, without
touching the two-view render from step 3.

{{code controls}}

## Step 5: Check both did their job

Every frame carries the same fixed overhead, such as the pass that composites
the picture. The combined frame's draw count still has to be higher than the
single, masked view's, because that is the one thing the extra view could add.
A frame that came back with the same count did not really draw a second view.

{{code check}}
