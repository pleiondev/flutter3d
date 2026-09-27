# Sheen

Velvet, felt and brushed cotton are made of fibres that stand up off the surface. Light
that grazes them bounces back towards you, so the cloth is brightest at its edges, where
you look along the fibres. A plain rough material gets darker towards its edges instead,
and cloth drawn with it looks like painted plastic.

The sheen layer adds that bright rim. This page draws the same red cloth twice, bare on
the left and with a sheen on the right.

## Step 1: A colour for the rim

The sheen has a colour of its own, and it does not have to match the cloth. Black means
no sheen at all, which is the default. The colour is linear, unlike the material's
`baseColor`: nothing paints it, so there is no authored sRGB form to convert from.

{{code colours}}

## Step 2: The cloth

`sheenColor` and `sheenRoughness` live in `MaterialExtensions`, which only
`LightingModel.pbrLayered` reads. The bare cloth on the left is the same model with no
extensions.

{{code cloth}}

Compare the two edges. The bare sphere darkens towards its outline; the right one keeps
a coloured rim there, strongest on the side the light reaches.

## Step 3: Change it while it runs

`MaterialExtensions` cannot be changed in place, so the page makes a new one each frame
from the controls and gives it to the material.

{{code live}}

Pick **White** and the rim reads as dust or fine fuzz; **Blue** on red shows plainly
which part of the light is the sheen. **Sheen roughness** changes how the rim spreads
across the sphere.

> **Note.** The light the sheen reflects is taken off what reaches the cloth beneath, so
> a bright sheen dims the base colour a little.
