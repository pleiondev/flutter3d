# Rough metals and rough clay

A metal-rough material treats a rough surface as a field of tiny facets. The usual model
counts one bounce of light off those facets and nothing after it, so the rougher the
surface, the more of its reflection simply goes missing. Rough gold comes out darker
than polished gold, which real gold does not do. The diffuse side has a problem of its
own. A constant diffuse lobe, Lambert's, looks the same from every angle you view it
at, so a sphere's shading follows only the angle to the light and falls off to a dark
rim. Real rough surfaces such as clay and plaster stay brighter towards the rim and
send more light back towards the light, as Oren and Nayar measured in 1994. Lambert
misses that, which makes them look like plastic.

Two frame settings fix these, one each. Both are off by default and both are arithmetic
in the shader, with no extra pass.

## Step 1: A row of gold

Five gold spheres, roughness 0.1 on the left up to 0.9 on the right. This is where the
missing light shows most.

{{code metals}}

## Step 2: A row of clay

Three grey spheres, not metallic, from half rough to fully rough.

{{code clay}}

## Step 3: One light

A single light from above and to the right of the camera. The ambient term is kept low
so that most of what you see is the light's.

{{code light}}

## Step 4: The two settings

`energyCompensation` puts back what the single bounce lost. It scales the direct
highlight by `1 + f0 * (1 / E - 1)`, where `f0` is the reflectance head-on and `E` is
the share of light one bounce keeps, which the shader already works out. It adds a
matching term to the environment's reflection. Dielectrics barely change; rough metals
brighten.

`diffuseModel` picks the diffuse lobe. `DiffuseModel.lambert`, the default, is the
constant one. `DiffuseModel.eon` is the energy-preserving Oren-Nayar lobe of Portsmouth,
Kutz and Hill (JCGT 2025, preprint 2024), rough by the material's own roughness. It
flattens the falloff across the sphere, lifts the side facing the light, and adds back
the light that bounces between the facets. The colour gets a little richer as the
surface roughens, which is that bouncing too. A smooth surface comes out the same as Lambert.

{{code settings}}

Switch **Energy compensation** off and watch the right end of the gold row: the rough
spheres go dim while the polished ones hardly change. Switch **Energy-preserving
diffuse** off and look at the clay: the shading across each sphere changes, most on the
roughest one.

> **Note.** `diffuseModel` changes only `LightingModel.pbr` and
> `LightingModel.pbrLayered`. The other lighting models keep their own diffuse.
