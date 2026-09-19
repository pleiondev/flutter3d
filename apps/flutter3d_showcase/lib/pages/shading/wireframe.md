# Wireframe

`RenderSettings.wireframe` asks the renderer to draw the scene's triangles as
lines instead of filled surfaces. It is a polygon mode, and only one of the
three backends this engine draws through actually has one: Impeller. WebGL2
has no `glPolygonMode`, and neither does the software rasteriser this page's
own test runs on.

That refusal is not silent. `FrameResult.wireframeDeclined` is true exactly
when a frame asked for wireframe and could not be given it, so a caller can
tell "nothing drew" apart from "the device cannot do this."

## Step 1: Something with edges worth seeing

A torus shows its wireframe better than a sphere does: the tube reveals how
the two rings of segments cross each other.

{{code mesh}}

## Step 2: Ask for it

One field, read every frame.

{{code settings}}

## Step 3: What actually happened

On a device that can draw lines, the knot now looks like a wire model. On
the software rasteriser, the knot still comes back solid, and
`wireframeDeclined` says why: the request was heard and could not be met.

{{code check}}

> **Note.** This is the one page in this set that leans on
> `Need.wireframe`. A device that lacks it still opens the page, with a
> note that part of what it describes will not show.
