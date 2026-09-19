# Many copies in one draw

Repeating one mesh with ordinary nodes costs a draw call per copy. An
`InstancedMeshNode` stores many transforms and colours in one vertex buffer, so
the renderer can submit the whole field together.

## Step 1: Allocate the batch

The node owns one capsule mesh, one material, and enough room for 64 instance
records. Capacity is explicit, which keeps a known-size field from reallocating
while it is filled.

{{code batch}}

## Step 2: Add transforms and colours

Each record contains a transform in the batch's local space and an RGBA colour.
The colour multiplies the mesh's vertex colour, letting copies differ without
separate materials.

{{code instances}}

## Step 3: Add one node to the scene

The scene receives the batch rather than 64 mesh nodes. Culling treats its
bounds as the union of every instance, while the scene renderer encodes one
instanced draw for the visible field.

{{code scene}}

## Step 4: Move the whole field

Instance transforms stay unchanged while the node rotates. Moving the batch
therefore changes one node transform instead of rewriting all 64 records.

{{code motion}}

## Step 5: Read the frame count

`FrameResult.instances` counts each copy even though they share a draw. The
page checks that all 64 records are present and reached the rendered frame.

{{code check}}
