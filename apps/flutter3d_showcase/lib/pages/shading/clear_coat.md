# Clear coat

Car paint, a varnished table and a glazed tile all have the same build: a coloured layer
underneath and a thin clear one on top. The colour can be matte while the top layer still
throws back a small, sharp highlight. One roughness cannot describe both, so the layered
material gives the top layer a roughness of its own.

This page puts the same red paint side by side, bare on the left and coated on the right.

## Step 1: Two paints, one with a coat

The clear coat lives in `MaterialExtensions`, the object that holds the material layers
glTF adds on top of metal and rough. Only `LightingModel.pbrLayered` reads it; a material
that has extensions and asks for plain `LightingModel.pbr` is drawn without them.

`clearcoat` is how much of the coat lies over the paint, from nought to one.
`clearcoatRoughness` is the coat's own roughness, separate from the paint's. Every field
of `MaterialExtensions` defaults to the value that changes nothing, so the bare paint on
the left is the same layered model with no coat at all.

{{code paint}}

## Step 2: Two spheres and a light

Both spheres share one mesh. The light comes from the upper right, a little behind the
camera, so each sphere shows its highlight on the side facing you.

{{code spheres}}

Look at the right sphere. The paint's own broad, soft highlight is still there, and the
coat adds a second, small one on top. The coat is colourless, so its highlight is white
over red paint.

## Step 3: Change it while it runs

`MaterialExtensions` is immutable, so the page builds a new one each frame from the
sliders and hands it to the material. The paint's roughness is an ordinary field of the
material, the same on both spheres.

{{code live}}

Raise **Paint roughness** and the paint goes matte on both sides, while the coat keeps
its sharp highlight on the right. Raise **Coat roughness** and that highlight spreads
out. Take **Coat** to nought and the right sphere matches the left.

> **Note.** The coat's reflection takes a share of the light, and the paint beneath gets
> what is left, so at a grazing angle a coated surface shows more of the coat and less
> of the colour. The coat is lit on the geometric normal, before any normal map is
> applied: a normal map on the paint does not bend it, and the coat's own normal map,
> `clearcoatNormalTexture`, is carried but not drawn.
