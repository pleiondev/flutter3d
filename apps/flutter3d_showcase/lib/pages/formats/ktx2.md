# KTX2 and Basis textures

KTX2 is the container most compressed-texture pipelines write to. Some
files carry a real GPU block format directly; others carry Basis
Universal, a format transcoded at load time into whatever the device
actually samples. This page reads one of the second kind.

## Step 1: Parse the container

This file's `vkFormat` is left undefined, which is how KTX2 says "these
pixels are Basis Universal" rather than naming a block format directly.
The container's own data format descriptor says which Basis flavour it
is; this one is ETC1S under Basis-LZ, and `Ktx2Texture.parse` transcodes
it to plain RGBA8 rather than handing back bytes nothing has asked a
device about yet.

{{code parse}}

> **Note.** UASTC is the other Basis flavour this reader knows, added
> later. A file naming a real block format directly, BC1 or ETC2 among
> them, skips transcoding altogether: its bytes are already what a device
> samples, once the device says it can.

## Step 2: Read what came back

`Ktx2Texture` answers the file's own dimensions, its `vkFormat`, and one
`ByteData` a mip level, largest first.

{{code report}}

## Step 3: Check the claim

A Basis file should never come back with its own undefined `vkFormat`
still on it, and this particular file is named for carrying more than
one mip level.

{{code check}}
