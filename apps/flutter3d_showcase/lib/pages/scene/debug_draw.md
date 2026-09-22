# Debug drawing

Debug overlays expose the data behind a frame without changing the model.
This page can draw the capsule's bounding box and normals, mark the world axes
and light, and trace a small joint hierarchy.

## Step 1: Keep the source mesh

The capsule uses `VertexLayout.skinned`, so its buffer has the joint and weight
attributes expected by the skinned vertex stage. It is uploaded with its source
data, which is the default. Bounds can be read from the device mesh, but the
normal overlay needs the original vertex positions and normals.

{{code model}}

## Step 2: Attach a skeleton

Skeleton debug drawing follows ordinary `SceneNode` joints. The example links
three joints, records their inverse bind matrices, and assigns the resulting
`Skeleton` to the mesh. The overlay will draw a small bone between parents and
children, plus a cross at a leaf joint.

{{code rig}}

## Step 3: Assemble the scene

The joint root, capsule, and point light all belong to the same scene. This is
enough information for the renderer to find the mesh bounds, vertex normals,
light position, and current joint transforms.

{{code scene}}

## Step 4: Select the overlays

`DebugDrawOptions` is part of `RenderSettings`, so it can change from one frame
to the next. A fixed `normalLength` keeps the orange normal segments readable
on this model; zero would let the renderer choose a length from the scene size.

{{code options}}

## Step 5: Toggle each layer

The controls change only the option fields. They do not rebuild the scene or
its meshes. This makes it practical to isolate one kind of diagnostic while
the camera and model stay put.

{{code controls}}

## Step 6: Check the overlay pass

`FrameResult.debugLines` reports how many line segments the renderer built.
The page checks that the rig has three joints and that the active overlays
produced more lines than the skeleton would produce on its own.

{{code check}}
