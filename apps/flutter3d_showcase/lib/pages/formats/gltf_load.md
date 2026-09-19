# glTF and GLB

glTF is the format most tools export to, and GLB is the same thing packed
into one binary file: JSON, geometry, and images in a single blob. This page
reads a real GLB and draws what comes out of it.

## Step 1: Read the bytes and decode them

A GLB carries everything it needs in one file, so there is no sibling to
resolve before decoding starts. `GltfLoader.load` reads the container, walks
its accessors and hands back a `GltfAsset`: a document of surfaces,
materials, and, when the file has them, lights and cameras.

{{code load}}

> **Note.** The loader also understands `.gltf`, the JSON-and-siblings form,
> `EXT_meshopt_compression`, `KHR_draco_mesh_compression`, and the basic
> `KHR_materials_unlit` and `KHR_lights_punctual` extensions. This file needs
> none of that: it is one mesh and one material, on purpose, so the loader's
> own work is what shows.

## Step 2: Upload each surface

A decoded document is not yet anything a device can draw. Each surface's
mesh becomes a `DeviceMesh` on the GPU, and its material's few numbers
become an engine `Material`. This page does that by hand, one surface at a
time, so nothing hides between the loader and the screen.

{{code upload}}

A real application usually skips this step and calls `ModelAsset.fromDocument`
instead, which also uploads textures and keeps meshes and images from being
uploaded twice. The `model-asset` page shows that path.

## Step 3: Check that something actually loaded

A loader that silently returns an empty document is worse than one that
throws, because nothing downstream notices until the screen is blank. This
page's own claim is that the file decoded to at least one surface with at
least one vertex, and that the frame actually drew it.

{{code check}}
