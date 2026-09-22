# Ambient occlusion

A corner facing the sky is exactly as bright as a wall facing it; a corner
tucked behind a shape sees less of that sky and should read a little darker.
Ambient occlusion is the pass that darkens the ambient light in exactly those
places, from nothing but the shapes already in the frame.

## Step 1: Give ambient light something to darken

The effect multiplies the scene's ambient term, so it has nothing to show
against the tiny default. Raising `ambientIntensity` is what makes the
darkening visible at all.

{{code ambient}}

## Step 2: Turn the pass on

`AmbientOcclusionSettings.enabled` runs the pass, and `strength` is how dark a
fully enclosed corner goes, from nothing at zero to nearly black at one. Drag
Strength down and the shadow at the base of the shapes softens back into the
floor.

{{code settings}}

## Step 3: Smooth the sampling pattern

Every occlusion pass samples a handful of points around each pixel, and a low
sample count reads as a speckle rather than a smooth gradient. `blurTaps` runs a
blur over the result that stops at silhouettes, so the dark of a corner does
not bleed onto whatever is standing in front of it. Zero is no blur. Turn Blur
taps up from zero and the speckle around the base of the ring smooths out.

{{code ran}}

> **Note.** Reading the occlusion needs the surface buffer, and on some devices
> that turns multisampling off for the whole frame. The automatic
> multisampling page has the details.
