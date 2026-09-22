# Procedural shapes

Small primitives do not need an asset pipeline. A shape value produces
`MeshData` on the CPU, which can be uploaded and used by an ordinary
`MeshNode`. This page builds five shapes from code.

## Step 1: Describe the geometry

Each shape keeps the numbers that define it. Segments and rings control how
closely a curved mesh follows the ideal surface. A cuboid needs only its size.

{{code descriptions}}

## Step 2: Build and upload each mesh

Calling `build` returns CPU-side vertices and indices. `DeviceMesh.upload`
moves that data to the active graphics device. From there the mesh uses the
same material and scene path as a model loaded from a file.

{{code build}}

## Step 3: Light the surfaces

A directional key light makes normals and curved silhouettes readable. The
point light fills the darker side without flattening every shape into one
colour.

{{code lighting}}

## Step 4: Check the result

The page keeps the five nodes it created, checks their names, and confirms that
at least one draw reached the frame for each shape.

{{code check}}
