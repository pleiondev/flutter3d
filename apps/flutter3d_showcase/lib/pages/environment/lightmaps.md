# Lightmaps

An irradiance field and a probe both measure a room at runtime. A lightmap
is the older answer: somebody bakes the indirect light into a texture ahead
of time, once, and every frame after that only has to sample it. It is
finer than either runtime method, at the cost of never updating on its own.

## Step 1: Give the mesh a second coordinate

The lightmap is not sampled at the model's ordinary texture coordinate. It
is sampled at a second one, and this engine carries that second coordinate
in the vertex colour attribute rather than a third UV set: a brush face has
no vertex colour to lose, and it saves a whole vertex layout for two floats.
Here the lightmap UV is just a copy of the regular one.

{{code uv}}

## Step 2: Bind the bake

`Material.lightmap` is a texture like any other, and `MeshNode.lightmapped`
tells the renderer to read the mesh's colour attribute as a coordinate into
it rather than as a tint. The lightmap in this page is baked by hand: bright
over one corner of the floor, dim everywhere else.

{{code bake}}

## Step 3: Compare it against nothing

With the scene's own ambient light at zero and no lamp in it, the floor's
only source of colour is the bake. Turning the lightmap off should turn the
floor black.

{{code live}}

> **Note.** A lightmap and a reflection probe answer the same question
> twice if a wall reads both, so a lightmapped draw is never handed a probe.
> Whichever the wall keeps is added to the direct light, not chosen between.

Toggle **Lightmap on** and watch the corner near the bright texel go dark
along with the rest of the floor.
