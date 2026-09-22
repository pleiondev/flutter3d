# Mesh editing overlays

A modelling overlay is part of the interface, not part of the asset. It keeps
edges and handles readable, respects the surface depth, and can still reveal a
gizmo that passes behind the model.

## Step 1: Register the contributor

`MeshOverlay` draws inside the scene pass, where the depth buffer is available.
It uses the renderer's debug-line shaders and is registered once as a pass
contributor.

{{code contributor}}

## Step 2: Draw the editable surface

The cube is an ordinary mesh with an ordinary material. None of the selection
colours or handles are baked into its geometry, so clearing the overlay returns
the original surface unchanged.

{{code surface}}

## Step 3: Follow the camera

Points and ribbons are measured in screen pixels. After the camera moves, the
overlay reads its eye, right, and up directions and converts one screen pixel
to a world-space size. The batches are then rebuilt without touching the cube.

{{code camera}}

## Step 4: Fill the three batches

Thin edges go into `lines`. Square vertex handles and the selected diagonal go
into `handles`. The two translucent triangles over the front face go into
`fill`. Each non-empty batch costs one draw, regardless of how much geometry it
contains.

`throughGeometry` writes a second copy of the purple gizmo without a depth
test. Its lower opacity shows where the handle continues behind the cube.

{{code batches}}

## Step 5: Change the editing view

The controls independently hide vertex handles, the selected face, and the
through-mesh gizmo. The edge cage remains visible as the stable outline of the
editable topology.

{{code controls}}

## Step 6: Check the submitted batches

The page checks the expected vertex counts for all three ordinary batches and
requires both through-mesh batches to contain geometry. The frame must also
include their draw calls alongside the cube and composite.

{{code check}}
