# Texture transform

`KHR_texture_transform` lets a material move, scale or rotate a
texture's coordinates without touching the texture itself, the case an
atlas export needs when every material sampling one packed image has to
read from its own corner of it. This page applies one to a plain mesh.

## Step 1: A texture to see the transform on

An 8x8 checker, small enough that a scale of four tiles it visibly
across the plane instead of stretching one copy over the whole surface.

{{code checker}}

## Step 2: Apply the transform to the mesh

`withTextureTransform` moves a mesh's own texture coordinates by the
extension's own order: scale, then rotate, then offset. It returns a new
`MeshData` rather than editing the one it was given.

{{code transform}}

> **Note.** This is not what a decoder does. A decoded document keeps
> the coordinates the file had beside the transform it named, so writing
> the document back out gives the file back. Applying the transform is
> what draws the surface correctly, and it happens here, at upload.

## Step 3: Check the claim

The plane's own corner, at U equal to one before the transform, should
come back at exactly four.

{{code check}}
