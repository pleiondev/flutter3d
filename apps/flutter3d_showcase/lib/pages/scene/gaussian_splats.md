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
