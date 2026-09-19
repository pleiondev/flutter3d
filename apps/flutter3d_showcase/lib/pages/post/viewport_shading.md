# Viewport shading

Sometimes the picture you want is not the lit scene but a fact about its
shape: which way each surface faces, where an edge is, how sharply it curves.
The scene pass already writes a world normal and a view-axis depth into a
second buffer for other effects to read, and viewport shading is arithmetic
on that buffer rather than another traversal of the scene.

## Step 1: Pick a mode

`ViewportShadingSettings.mode` chooses what to show. `normals` colours every
pixel by the direction its surface faces. `clay` lights the scene with one
studio light over a neutral grey, which is what a sculptor turns on to read
shape without colour in the way.

{{code settings}}

## Step 2: Read edges and curvature

`outline` draws a dark line where depth or normal makes a sudden step.
`curvature` lightens a ridge and darkens a crease from how fast the normal
field turns. Cycle through the modes and watch the ring: in `normals` it
becomes a smooth gradient of colour, in `clay` it loses its gold and becomes a
plain grey form, in `outline` its silhouette gets a dark edge, and in
`curvature` the tight bend of the tube reads brighter than the flat floor.

{{code settings}}

## Step 3: Confirm the mode ran

`off` is an exact no-op and the pass does not run at all. Any other mode
should appear in `FrameResult.passes`.

{{code ran}}

> **Note.** Because this reads the same second buffer ambient occlusion does,
> a mode other than `off` also costs the frame its multisampling, on a device
> that would otherwise have it.
