# Loading into a scene

`GltfLoader`, `ObjLoader` and every other reader in this engine produce a
`ModelDocument`: geometry, materials and a hierarchy, still on the CPU.
`ModelAsset.fromDocument` is the one path from there onto a GPU, whatever
format the document came from.

## Step 1: A decoded document

This page builds its own rather than reading a file, but the shape is
exactly what a real loader hands back: surfaces, a material, and a node
naming each one.

{{code document}}

## Step 2: Upload it once

Meshes and images are shared by identity, so a document that reuses one
mesh across several surfaces uploads it once. Materials come out as the
engine's own `Material`, with textures resolved and bound.

{{code upload}}

## Step 3: Place it in a scene

An asset is immutable and GPU-resident; `instantiate` is what puts it
somewhere. Calling it twice makes two independent instances that share
the same uploaded mesh, which is the reason the asset and the instance
are two different things: loading a model twice would upload it twice.

{{code instantiate}}

## Step 4: Check the claim

The asset has to have actually uploaded something, `instantiate` has to
have added a mesh to the scene, and the frame has to have drawn it.

{{code check}}
