# Normal maps

A normal map fakes relief. Instead of building thousands of triangles for every
bump, you store in a texture which way the surface faces at each point, and the
light is computed as if the bumps were there. The ball on this page is a smooth
sphere that looks cobbled.

## Step 1: Write the directions into a texture

Each texel holds a direction as three numbers from -1 to 1, stored as red, green
and blue from 0 to 255. Flat ground is the colour `(128, 128, 255)`, which is why
normal maps look blue. Here the code makes round cobbles in a grid, with a flat
gap around each one.

{{code texture}}

In a real project this texture comes from a file. Building it here keeps the page
self contained.

## Step 2: Upload it with its mip chain

`createTextureFromPixels` puts the pixels on the device. `MipChain.build` makes
the smaller copies that the sampler uses when the surface is far away or turned
from the view, so the bumps fade instead of shimmering.

{{code upload}}

## Step 3: Give the map to a material

`Material.normal` takes the texture and `normalSampler` says how to read it.
`normalScale` multiplies the sideways part of every direction: zero flattens the
relief, one is the map as painted, and larger values exaggerate it.

{{code material}}

## Step 4: The mesh needs tangents

A direction stored in a texture is measured against the surface, so each vertex
needs a tangent that says which way the texture's x axis runs. The engine's
shapes already carry them. `withGeneratedTangents` adds them to a mesh that has
positions, normals and texture coordinates but no tangents, which is what a
model loaded from a plain OBJ file looks like.

{{code tangents}}

## Step 5: Change it while it runs

Drag Normal scale and the relief grows and vanishes. Turn the Normal map switch
off to see the bare sphere, and drag Sun direction to sweep the light across the
cobbles: the bumps light on one side and darken on the other, which is what tells
your eye they stand out.

{{code live}}
