# Anisotropic texture filtering

Look along a floor at a low angle and each pixel covers a sliver of texture: a few
texels wide and many long. Ordinary filtering picks one blur level for the whole
sliver, and either the checks go grey in the distance or they shimmer.
Anisotropic filtering takes several samples along the long direction instead, and
the far checks stay checks.

## Step 1: A texture with a mip chain

The filter works across mip levels, the successively halved copies of a texture,
so the texture has to have them. `CheckerboardTexture` makes the pixels and
`MipChain.build` makes the chain, and both go to the device together.

{{code texture}}

## Step 2: A sampler that blends the levels

Anisotropy needs linear filtering between mip levels too, which is what
`SamplerOptions.trilinearRepeat` is. Repeat addressing lets the same texels cover
a floor of any size. The material and the mesh are otherwise ordinary.

{{code floor}}

> **Note.** A sampler that is not trilinear is left alone by the setting below.
> There is nothing to spread taps across when the lookup is nearest.

## Step 3: Ask for the taps

`RenderSettings.anisotropy` is how many taps a sample may take along the long
axis. One is the plain trilinear look. The engine applies the value when it binds
each material sampler and clamps it to what the device offers, so asking for 16 is
safe everywhere.

{{code settings}}

Choose 1x and look at the horizon: the checks blur into a grey band. Choose 8x
or 16x and they stay crisp much further out. The picture near your feet does not
change, because there the footprint is almost square.
