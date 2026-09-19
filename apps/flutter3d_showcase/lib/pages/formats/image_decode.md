# Image decoding without dart:ui

`flutter3d_core` cannot import `dart:ui`: it has no window, and a texture
node's own bake needs pixels somewhere that does not require one either.
So PNG, JPEG and Radiance `.hdr` are each read by a decoder written here,
not borrowed from Flutter. This page runs all three.

## Step 1: A real JPEG, encoded elsewhere

This is a real, quality-100 JPEG of a flat colour, one 8x8 block, the
smallest a baseline JPEG can be.

{{code jpegSource}}

## Step 2: Encode a PNG, and decode it back

Unlike the JPEG, the PNG here is built by this page: `encodeCompressedPng`
writes a small checkerboard, and `decodePng` reads it straight back.

{{code png}}

## Step 3: Decode the JPEG

`decodeJpeg` is this package's own baseline decoder: Huffman tables,
chroma upsampling, the inverse DCT, all of it. A flat fill has no block
edges to hide a rounding error behind, which is why the source file is
exactly that.

{{code jpeg}}

## Step 4: Decode a hand-built HDR

Radiance's `.hdr` stores three floats a pixel as four bytes: a shared
exponent and three mantissas. This file is two pixels wide, which is
under the width the newer run-length form requires, so it is written the
old, flat way: a header, then every pixel's four raw bytes in order.

{{code hdr}}

## Step 5: Read the numbers back

Three decoders, three answers, none of them touching `dart:ui`.

{{code report}}

## Step 6: Check the claim

The PNG has to survive its own round trip, the JPEG has to decode close
to the colour it was encoded from, and the HDR pixel has to come back
brighter than black.

{{code check}}
