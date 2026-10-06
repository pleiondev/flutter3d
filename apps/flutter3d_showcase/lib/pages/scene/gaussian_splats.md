# Gaussian splats

A Gaussian splat represents a soft, oriented ellipsoid instead of a hard
triangle. A fitted cloud can reproduce a captured scene from many small,
overlapping splats whose colours and opacity blend together.

## Step 1: Prepare a tiny cloud

The sample contains 35 splats arranged as a shallow wave. Each row starts with
plain positions, linear colours, opacity, and three ellipsoid scales so the
fixture remains readable.

{{code rows}}

## Step 2: Decode the PLY

Capture tools store splats in binary PLY files. `parseSplatPly` handles three
conventions that the header does not express: opacity is a logit, scales are
logarithms, and colour channels are zeroth-band spherical-harmonic
coefficients. The result is a `SplatCloud` with flat, render-ready arrays.

{{code decode}}

## Step 3: Add the drawing contributor

`SplatContributor` joins the scene pass after opaque meshes. It sorts the
cloud back to front for the active view, rebuilds one quad per splat, and draws
the whole cloud with alpha blending and no depth write.

{{code contributor}}

## Step 4: See the file layout

This helper writes the same 14 float properties used by fitted-splat PLY
files. It converts readable colour, opacity, and scale values back to their
stored forms, then writes every float in little-endian order after the text
header.

{{code ply}}

## Step 5: Check sorting and drawing

The page checks the decoded count, one six-vertex quad per splat, and a sorting
result that contains every splat exactly once. It also requires the contributor
to add its draw call to the frame.

{{code check}}

## Step 6: Sort on the GPU where the device computes

Sorting is the part of a splat cloud that grows with the capture. Where the
device has compute shaders, which today means WebGPU, `SplatContributor`
sorts on the GPU instead: two radix passes over the depth keys, and the last
pass writes the index buffer the draw reads, so the order never comes back
to the CPU. Every other device, including Impeller, WebGL2 and the software
renderer, keeps the CPU sort. The CPU sort is the reference: the GPU's order
matches it splat for splat, and the picture is the same to the byte.

`gpuSort` is on by default and takes effect only where the device can run
it. **GPU sort** turns it off, which on WebGPU sorts on the CPU instead and
anywhere else changes nothing. A cloud larger than `kSplatGpuSortLimit`
splats stays on the CPU too.

{{code gpu}}

The page checks that the cloud was drawn in the GPU's order exactly when the
toggle is on and the device can sort. On the software device that runs the
page's test, that is never.

{{code gpu-check}}
