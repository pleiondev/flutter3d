# A face per copy

An ordinary morph weight lives on the node, so one draw of one mesh always
shows one shape. A batch is one draw of many copies, and the ordinary weight
would give every copy in it the same shape too. `InstancedMeshNode
.setMorphWeights` is the way out: each copy gets its own weights, read from a
texture by instance id rather than from a uniform.

## Step 1: A batch that can grow

`InstancedMeshNode` takes a mesh, a material and how many copies it can hold.
Each copy still shares the one delta texture the mesh was packed with — that
part is exactly what an ordinary morph target already is — but from here each
copy can be told how much of it to wear.

{{code batch}}

## Step 2: A weight for every copy

Each frame writes a different weight into each instance's own slot. The
weights do not sit in the instance record next to the transform: they ride in
a second texture, rebuilt only when a weight actually changed.

{{code live}}

## Step 3: Watch a shared draw wear six faces

The batch from step 1 is still one draw call, whatever each instance's own
weight says.

{{code batch}}

Drag Spread from nought. At nought every face sits flat: the deltas are
there, but every instance's own weight is nought. As Spread rises, the face
at one end stays flat while the one at the other end grows its full bump, and
the ones between it show every step in between, each read from its own row of
the weights texture rather than from the mesh's shared uniform. All six still
come from the one draw call `frame.instances` reports.
