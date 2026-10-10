# Draw control

Three small controls over how a mesh is drawn. `MeshNode.drawOrder` decides
which of two nodes goes first, even when they share a material.
`Material.alphaToCoverage` smooths the edge of a masked surface where the
device can do it. And `PassEncoder.draw` can read a window of the bound index
buffer, so one buffer that holds every part of a model can be drawn a part at
a time.

On the left of this page, a red panel and a blue panel stand in exactly the
same place. On the right is a grille cut from a small texture.

## Step 1: Two meshes in one place

The two panels use the same mesh and the same transform, so every pixel of
one is also a pixel of the other, at the same depth. The scene pass keeps a
fragment only when it is nearer than what is already there, and an equal
depth is not nearer. So the first panel drawn keeps every shared pixel.

{{code panels}}

## Step 2: Say which goes first

Lower draws first. The node's `drawOrder` is added to its material's
`drawBucket`, and that sum is the first field of the sort key, ahead of the
pipeline, the material and the depth. The batching never merges a run of
identical draws across two orders, so a batch cannot undo the order either.
Switch **Drawn first, and so seen** and the other colour takes the panel.

{{code order}}

## Step 3: A masked edge as coverage

The grille is a 16 by 16 texture with a grid of round holes in its alpha,
drawn with `MaterialAlphaMode.mask` and a cutoff of a half. Without coverage
each pixel is either kept or cut, which leaves a staircase round every hole.
With `alphaToCoverage` the alpha is sharpened to about a pixel's width round
the cutoff and handed to the multisample resolve as coverage, so the holes
come out as smooth as a triangle's edge.

{{code grille}}

Only WebGL2 and WebGPU can do this, and only in a scene pass that
multisamples. Impeller has no control for it and the software rasteriser
draws one sample, so there the grille is drawn with its hard cutoff and
`FrameResult.alphaToCoverageDeclined` is true.

## Step 4: A window of the index buffer

The meshes in a scene draw their whole index buffer. Code that encodes its
own pass, such as a `PassContributor` or a frame graph node, can call
`PassEncoder.draw(firstIndex: ..., indexCount: ...)` to draw part of it. A
cube's 36 indices are six faces of six, so each face is one window.
`indexWindow` is the rule all four backends apply to such a call: a window
that runs past the end of the binding is refused with a `RangeError` before
any driver sees it.

{{code windows}}

## Step 5: What the page checks

The sorted draw list has to put the panel with the lower order first. On a
device without coverage, the frame has to say the grille's coverage was
declined. The six windows have to cover the whole index buffer, and a window
of twelve indices starting at the thirtieth has to be refused.

{{code check}}

> **Note.** The check reads the sorted list and the frame's flags, not the
> pixels, so which colour wins the shared panel is shown on screen rather
> than tested here. The page cannot show coverage working on the software
> device the tests use, only the refusal. Per-draw windows have no setting on
> `MeshNode`: a scene mesh is always drawn whole, and a window is for code
> that writes its own pass.
