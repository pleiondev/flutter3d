# glTF and GLB

glTF is the format most tools export to, and GLB is the same thing packed
into one binary file: JSON, geometry, and images in a single blob. This
page writes a small GLB with this engine's own writer, then reads it back
with the loader to show what a real file decodes into.

## Step 1: A real GLB to read

Two surfaces, two materials, and a node each. Writing it here means this
page needs no bundled asset, only the same writer the `gltf-write` page
exercises directly.

{{code write}}

## Step 2: Decode it

A GLB carries everything it needs in one file, so there is no sibling to
resolve before decoding starts. `GltfLoader.load` reads the container,
walks its accessors and hands back a `GltfAsset`: a document of surfaces,
materials, nodes, and, when the file has them, lights and cameras.

{{code load}}

> **Note.** The loader also understands `.gltf`, the JSON-and-siblings
> form, `EXT_meshopt_compression`, `KHR_draco_mesh_compression`, and the
> basic `KHR_materials_unlit` and `KHR_lights_punctual` extensions. This
> file needs none of that, so the loader's own ordinary path is what shows.

## Step 3: Upload each surface, at the node that places it

A decoded document is not yet anything a device can draw. Each surface's
mesh becomes a `DeviceMesh`, its material's few numbers become an engine
`Material`, and the node hierarchy says where each one sits.

{{code upload}}

A real application usually skips this step and calls `ModelAsset.fromDocument`
instead, which also uploads textures and keeps meshes and images from being
uploaded twice. The `model-asset` page shows that path.

## Step 4: Check that both surfaces actually loaded

A loader that silently drops a surface is worse than one that throws,
because nothing downstream notices until the screen is missing an object.
This page's own claim is that both surfaces came back and both were drawn.

{{code check}}
