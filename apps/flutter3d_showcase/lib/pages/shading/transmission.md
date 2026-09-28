# Glass that shows the scene

A see-through material made with alpha blending lets the background through, but only
the background exactly behind it, unchanged. Real glass does more: frosted glass blurs
what is behind it, and a thick lump of glass bends it. Both need the glass to read the
picture behind it, not just mix with it.

The transmission layer does that. On a frame with glass in it, the renderer draws
everything opaque first, keeps a copy of that picture, and then draws the glass reading
the copy. Alpha-blended surfaces come after the glass, in the same `transparent` pass,
so they are not in the copy.

## Step 1: Something to look through

A wall, red on the left and blue on the right, with pale stripes across it. The wall is
unlit so its colours stay flat, and the stripes give a blur and a bend some edges to
act on.

{{code wall}}

## Step 2: Two pieces of glass

Both are `LightingModel.pbrLayered` with a `transmission` in `MaterialExtensions`.
`transmission` is how much of the light that is not reflected goes through the surface
instead of scattering off it: one is clear glass, nought is an ordinary surface.

The pane on the left has a `thickness` of nought, which the renderer treats as a thin
wall: it reads the copy straight behind each pixel. The ball on the right has a
thickness, in the mesh's own units, so the ray bends at its surface by the index of
refraction `ior` and travels that far before it reads the copy. The default `ior` is
1.5, about the value for window glass.

{{code glass}}

## Step 3: Change it while it runs

The page builds new extensions each frame from the sliders. The pane keeps a thickness
of nought; the ball takes the slider's.

{{code live}}

Look at the stripes through the ball: they curve and shift, and the pane beside it shows
them straight. Raise **Roughness** and both go frosted. The copy is kept at its full size
and at five halvings, and a rougher surface reads a smaller, blurrier one. Bring the
**Index of refraction** down to 1 and the ball stops bending the stripes and the blur goes
away as well: the renderer scales the blur by how far the index is above 1, up to 1.5.

> **Note.** A frame with glass in it is drawn without multisampling, because the second
> half cannot load what the first half left in the multisampled targets.
> `FrameResult.antiAliasing.msaaDeclined` says so. Set **Transmission** to nought and the
> frame goes back to being drawn in one pass.
