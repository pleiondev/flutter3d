# A texture transform per map

glTF lets a file move, scale and turn each texture of a material on its own, through the
`KHR_texture_transform` extension. Often every map of a material gets the same transform,
an atlas export for example, and then the engine can simply move the mesh's texture
coordinates once when it loads. When the maps disagree there is no single set of
coordinates that suits all of them, so each map needs its own transform, applied when
the map is read.

This page draws two plates with the same four-colour texture as both their colour map
and their glow map. The left one reads both maps as they are. The right one moves each
map a different way.

## Step 1: A texture you can read the orientation of

Two by two texels, red, green, blue and white, sampled without filtering and with
repeat, so every texel is a sharp square and a tiled copy shows as more squares.

{{code texture}}

## Step 2: A transform for each map

A `TextureTransform` has an `offset`, a `scale` and a `rotation` in radians. They apply in
the extension's order: a coordinate is scaled, then turned about the texture's origin,
then moved by the offset. `MaterialMap` names which map a transform is for: the colour
map, the metal and roughness map, the normal map, occlusion or the glow.

Here the colour map is tiled and turned, and the glow map is slid sideways.

{{code transforms}}

## Step 3: Two plates

The same texture is the colour map (`albedo`) and the glow map (`emissiveTexture`) of
both plates. The right one takes the transforms in `textureTransforms`. A map with no
entry there is read at the mesh's own coordinates, which is why the left plate shows the
texture once and straight.

`textureTransforms` is read only by `LightingModel.pbrLayered`. The other lighting models
ignore it.

{{code plates}}

## Step 4: Change them while it runs

`textureTransforms` is an ordinary map on the material, so the page writes new entries
into it every frame from the sliders.

{{code live}}

On the right plate the glowing squares no longer line up with the coloured ones. Turn
**Colour map: turn** and only the colour pattern turns; move **Glow map: slide** and only
the glow moves.
