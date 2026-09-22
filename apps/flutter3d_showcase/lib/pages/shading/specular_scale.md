# Specular strength

`RenderSettings.specular` is a single number the whole frame reads. It scales
the specular response of every material in the scene, without touching a
single one of them. Turn it down and every highlight in the picture goes with
it. Turn it up and the same materials look wetter or more polished, with no
change to their own roughness or metallic values.

## Step 1: A ball worth putting a highlight on

A high metallic value and a low roughness give a surface a tight, bright
highlight. That is the surface this page turns the knob on: something with a
highlight to show in the first place.

{{code material}}

## Step 2: One light

A single directional light is enough to put a highlight somewhere on the
ball. Move the view and the highlight moves with it, the way a real
reflection would.

{{code light}}

## Step 3: The knob

`RenderSettings.specular` is read every frame, so the slider only has to
change one field.

{{code settings}}

At `0` the ball is flat, unlit-looking on its bright side. Above `1` the
highlight gets sharper and brighter than the material alone would ever
produce, because this multiplies what the material's own shading already
computed.

## Step 4: What this page checks

The test behind this page cannot compare two pictures, so it checks the
setup it can: the material really is metallic and smooth enough to carry a
highlight, and the frame drew it.

{{code check}}
