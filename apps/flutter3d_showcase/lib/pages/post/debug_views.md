# Debug views and render stats

When a surface looks wrong, the lit picture rarely says why. The albedo may
be too bright, a metalness map may have been read as sRGB, or a seam may run
through the UVs. `RenderSettings.debugView` shows one material channel in
place of the light, over all of the frame or the right part of it, so the
lit picture and the channel can be compared in a single frame. The frame then
says what it cost: draws, triangles, the bytes its targets hold, and the same
numbers pass by pass.

## Step 1: The channels

There are eight channels besides `DebugView.off`. Albedo is the base colour
after its texture and tint. Normal is the shading normal after the normal
map, as `n · 0.5 + 0.5` in world space. Roughness, metalness and occlusion
are greys. Emission is its own colour, clipped at one. UV is the base map's
coordinate in red and green, so a seam shows as a step in colour.
`nonFinite` is magenta wherever the light came out NaN or infinite, and a
dark grey of the light's brightness everywhere else.

{{code channels}}

The stage has one thing that gives off light, so the emission channel has
something to show.

{{code glow}}

## Step 2: Wipe between the light and a channel

`DebugViewSettings` takes the channel and a `split`, the share of the width
left lit. Nought shows the channel over the whole frame; a half keeps the
left half lit. The materials write the channel themselves, before they write
their light, so it shows what the maps did rather than what a buffer kept.
The composite leaves the debug side out of the exposure, the tone curve, the
bloom and the grade.

{{code view}}

Drag **Split** to move the wipe, or leave **Step through the channels** on
and the page moves to the next channel every two seconds.

## Step 3: What the frame cost

`FrameResult` has the totals: `drawCalls`, `triangles`, `instances` and
`pipelineSwitches`. `FrameResult.passes` has the same numbers for each pass of
the frame graph, plus its CPU time and its GPU time where the device measures
it. `targetBytes` counts every texture the frame drew into or read from, each
once: its base level, every slice and every sample. `textureBytes` is how a
single texture is counted, so a caller can count its own.

The page checks that the pass costs add up to the frame's totals, that the
composite is a single draw, and that the targets hold at least as many bytes
as the picture handed back. The scene's own colour target is that large on
its own.

{{code stats}}

> **Note.** Only lit materials write a channel. The sky, particles, splats
> and glass's own pass draw as they always do, and on the debug side they
> reach the screen without the tone curve, so they look brighter there.
> Reflections, depth of field, motion blur and a temporal resolve still run
> over the channel, so turn them off for a clean reading. `targetBytes` does
> not count mip chains. Whether Metal, compiled with fast math, keeps the NaN
> comparison has not been checked. The page's own check reads the counters,
> not the pixels: the split picture is held by the `debug-view-split`
> reference images on all four backends.
