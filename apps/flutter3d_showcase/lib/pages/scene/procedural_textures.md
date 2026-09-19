# Procedural textures

A small texture can be generated with no asset file or image decoder.
`SolidColorTexture` and `CheckerboardTexture` produce ordinary RGBA8 pixels,
then use the same upload path as any other CPU-side image.

## Step 1: Encode pixels on the CPU

`encode` returns four bytes per pixel in row-major order. A solid 1 by 1 image
needs four bytes; the 64 by 64 checkerboard needs 16,384. Checking those sizes
at the boundary catches a malformed custom texture before upload.

{{code encode}}

## Step 2: Upload through the active device

`upload` creates a device texture from the encoded bytes. The resulting handle
goes into `Material.albedo`. The checkerboard uses a repeating sampler, while a
single solid texel looks the same at every UV coordinate.

{{code upload}}

## Step 3: Use them on ordinary meshes

The blue texel covers a sphere. The checkerboard follows the UVs generated for
a torus, making its seam and surface direction visible without loading an
external image.

{{code scene}}

## Step 4: Check pixels and uploads

The page confirms that both material texture handles exist and that adjacent
checker cells have different RGB values. It then checks that both meshes were
drawn.

{{code check}}
