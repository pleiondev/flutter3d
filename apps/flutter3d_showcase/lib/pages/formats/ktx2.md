# KTX2 and Basis textures

KTX2 is the container most compressed-texture pipelines write to. Some
files carry a real GPU block format directly; others carry Basis
Universal, a format transcoded at load time into whatever the device
actually samples. This page reads one of the second kind and puts it on
a cube.

## Step 1: A real Basis Universal file

Eight by eight pixels, four flat-coloured quadrants, produced by a real
build of `basisu`. `vkFormat` is left undefined, which is how KTX2 says
"these pixels are Basis Universal" rather than naming a block format
directly; the container's own data format descriptor says which flavour,
ETC1S under Basis-LZ here.

{{code bitstream}}

## Step 2: Parse it

`Ktx2Texture.parse` transcodes the ETC1S data to plain RGBA8, checked
against a real `basisu -unpack` decode of the same file rather than only
against this reader's own understanding of the format.

{{code parse}}

> **Note.** UASTC is the other Basis flavour this reader knows. A file
> naming a real block format directly, BC1 or ETC2 among them, skips
> transcoding altogether: its bytes are already what a device samples,
> once the device says it can.

## Step 3: Put it on something

The transcoded level is already plain RGBA8, the same shape any other
decoded image arrives in, so it uploads the same way.

{{code upload}}

## Step 4: Check the claim

This fixture is always 8x8, always transcodes to RGBA8, and its
top-left quadrant is a near-pure red.

{{code check}}
