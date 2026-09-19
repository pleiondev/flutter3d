# Perspective and orthographic

A camera needs a rule for turning a point in the world into a point on the
glass. This engine ships two: perspective, where a thing shrinks as it moves
away, and orthographic, where its size on screen never changes. Both are a
`Projection` and both hand the camera a 4x4 matrix; what differs is the shape
of that matrix.

## Step 1: A box to look at

A plain cuboid, lit by one directional light. Nothing here is about the
projection yet: this is the geometry both lenses will draw the same way.

{{code box}}

## Step 2: The default lens

`PerspectiveProjection` is what a camera uses if you never ask for anything
else. `fovYRadians` is the vertical field of view, in radians; a wider angle
sees more of the scene and makes things at the edges bend more.

{{code perspective}}

## Step 3: The other lens

`OrthographicProjection` has no field of view. Instead it names a `height`:
how many world units the view spans from top to bottom, wherever the camera
stands. Move an orthographic camera closer and the picture does not zoom, it
only clips nearer geometry.

{{code orthographic}}

> **Note.** Switching lenses on a live camera is nothing more than assigning
> a new `Projection` to `CameraNode.projection`. Nothing else about the scene
> or the renderer needs to change.

The chip beside the viewport switches between the two so you can watch the box
stop shrinking with distance the moment orthographic is chosen.
