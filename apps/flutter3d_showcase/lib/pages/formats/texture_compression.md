# Compressing a texture

A raw RGBA8 texture is four bytes a pixel no matter what it shows. A
block-compressed one trades a little quality for a fixed ratio: sixteen
pixels become one block of a handful of bytes. This page compresses one
small image four different ways.

## Step 1: A source image

A checkerboard, sixteen pixels on a side so every mip level down to 4x4
still lands on a whole block boundary.

{{code source}}

## Step 2: Four encoders, one image

`encodeBc1` and `encodeBc3` are the two DirectX-style block formats, the
second carrying an alpha block the first does not. `encodeEtc2Rgb8` is
the format most Android GPUs prefer, and `encodeAstc4x4` is the newest of
the four, one fixed block size among several the real format supports.

{{code encode}}

## Step 3: A mip chain, and a container to hold it

`buildMipChain` halves an image with a box filter down to one pixel.
Everything past 4x4 is too small for a block encoder to take, so this
page stops there and writes what is left as a real KTX2 file with
`writeKtx2`.

{{code mips}}

## Step 4: Compare the sizes

Every encoder here should shrink the picture; the point of this page is
to see by how much.

{{code report}}

## Step 5: Check the claim

Every one of the four blocks has to be smaller than the pixels it came
from, and the container `writeKtx2` wrote has to actually be a file.

{{code check}}
