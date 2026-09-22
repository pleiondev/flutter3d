# Orbit

`OrbitController` already turns the camera as you drag, in every page of
this showcase. This page is about three things it also does that a drag
never touches: framing a model automatically, turning to a chosen angle over
time instead of snapping to it, and stepping that turn every frame.

## Step 1: Something to frame

A box, and its bounds as an `Aabb3`. `frameBounds` only needs the bounding
box, not the mesh itself, which is why picking a good bounding box matters
more than the shape inside it.

{{code bounds}}

## Step 2: Frame it

`frameBounds` moves the target to the box's centre and pulls the camera back
until the box fills the view, using the bounding sphere rather than the box
so the framing holds at any angle you orbit to afterwards.

{{code frame}}

## Step 3: Swing to a new angle

`animateTo` does not move the camera itself. It starts a smoothed turn that
`advance` steps forward each frame, so the view arrives at the new yaw and
pitch instead of jumping to them.

{{code swing}}

> **Note.** A turn started by `animateTo` stops the moment you drag the view
> by hand. A hand on the pointer always outranks an animation already in
> flight.

## Step 4: Step the turn

Nothing in `animateTo` moves the camera by itself; `advance` is what actually
turns it, a little further each frame, until the turn's own duration has
passed.

{{code advance}}
