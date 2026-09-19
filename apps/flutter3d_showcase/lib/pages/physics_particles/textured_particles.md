# Textured billboards

An untextured particle draws as a procedural disc: cheap, and the same shape
every time. Handing `ParticleContributor` a texture swaps in a sprite,
sampled per particle, and the sprite can be anything a texture can hold.

## Step 1: Paint one sprite

This one is drawn on the CPU, a spark shaped like a four-pointed star rather
than a circle: bright along its two axes, dark at the corners.

{{code sprite}}

## Step 2: Put it on the device

{{code texture}}

## Step 3: Hand it to the contributor

`null` picks the procedural disc; anything else picks the textured stage.
The two are different fragment shaders, not the same one with a white
default, because binding a texture to a slot a compiled shader has no room
for is expensive to get wrong.

{{code contributor}}

## Step 4: What changed

The page's own check is only that a texture is actually there: the shape a
sprite draws is a matter for your eyes, not for a test running headless.

{{code check}}

> **Warning.** Build a texture with a mip chain if you can, and check
> `GraphicsDevice.supportsMipmaps` first. A particle is a quad that shrinks
> as it recedes, and one without a chain sparkles on the way out.
