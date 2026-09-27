# Spatial upscaling

`RenderSettings.renderScale` draws the whole frame smaller to save time, and on
its own it hands back the smaller picture for the presenter to stretch. A
stretch blurs every edge. Spatial upscaling brings the small picture up to
full size with a filter that follows edges, then sharpens it, so the frame
costs a fraction of the pixels and still keeps its outlines.

## Step 1: A scene with edges

The shared stage: a floor, three shapes and a sun that casts shadows. The
outlines of the shapes and the shadow edges are what a stretch softens first.

{{code stage}}

## Step 2: Draw small, then scale up

`renderScale` is the share of each axis the scene is drawn at. At 0.5 the frame
has a quarter of the pixels. `RenderSettings.spatialUpscale` takes a
`SpatialUpscaleSettings`, off by default. With `enabled` on, a twelve-tap
edge-directed filter brings the finished picture up to the size you asked for,
after the tone map, and a contrast-adaptive sharpen follows it. `sharpen` is
how much that pass adds back, from nought to one, 0.2 by default. Nought skips
the sharpen.

{{code settings}}

Switch **Upscale** off and the edges of the block and the ring go soft. Switch
it on and they come back crisper at the same render scale. Drag **Render
scale** down to see where the filter runs out of detail to work with.

## Step 3: When it runs

The upscale only runs below a render scale of one, and only while temporal
anti-aliasing is off. The temporal resolve already rebuilds the frame at full
size from its jittered history, so it has no need of a second filter.

{{code runs}}
