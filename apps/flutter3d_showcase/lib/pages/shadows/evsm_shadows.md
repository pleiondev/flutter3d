# EVSM shadows

The sun's shadow map stores one depth per texel, and a pixel on screen learns whether
it is in shadow by comparing its own depth with a few of them. A soft edge means many
comparisons, and they are paid again by every pixel in every frame.

Exponential variance shadow maps (EVSM) move that work into the map. The map is turned
into moments of the depth, blurred once for the whole frame, and then each pixel reads
it back with one filtered tap. The soft edge is already in the blurred texture.

## Step 1: A post and a raised box

A post standing on the floor and a flat box whose underside is held half a metre above
it. The post's shadow starts where the post touches the floor. The box's shadow has
travelled the whole way down.

{{code casters}}

## Step 2: A sun that casts

The sun is a directional light, and a directional light asks for a shadow map by
default. The filter choice on this page applies only to the sun's map; point and spot
lights have their own soft path.

{{code sun}}

## Step 3: Three filters

`ShadowSettings.filter` picks how the sun's map becomes an edge. Null, the default,
picks from `directionalLightRadius`, as the renderer did before there was a choice.
The page names one of the three.

{{code filters}}

## Step 4: Compare them

`pcf` takes nine taps in a 3 by 3 square. The edge is as wide as the map's texels make
it, the same everywhere.

`pcss` first searches for what is blocking the light, then filters as wide as a light
of `directionalLightRadius` would leave, sixteen taps each way. The page sets that
radius to 0.02 radians, about four times the real sun's 0.0047, so the difference
shows. The post's shadow is sharp at its foot and spreads toward its tip.

`evsm` blurs the moments `evsmBlurRadius` texels to each side, from nought to eight;
the default is two, and the page starts at four. The edge is the same width
everywhere, because the blur belongs to the map and not to the pixel: unlike `pcss`,
it does not harden where the post meets the floor.

Where two casters overlap at very different depths, EVSM lets a faint halo of light
through the nearer one. `evsmBleedReduction`, from nought to 0.95 with a default of
0.2, treats everything under that share as full shadow. Drag **Bleed reduction** up
and the halo goes, and the soft edge darkens with it.

Switch **Filter** between the three and watch the post's shadow and the box's.

{{code settings}}

> **Note.** EVSM needs an rgba32f atlas and two more blur passes over it, paid only when
> the map changes. It also needs a device that can filter 32-bit float textures
> (`supportsFloat32Filtering`). A device without it refuses the filter: the pass named
> `shadow moments` shows up in `FrameResult.skipped` as unsupported, and the frame
> draws the 3 by 3 kernel instead.
