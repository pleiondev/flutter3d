# Planar reflections

Screen-space reflections can only show what is already on the screen, and a
reflection probe is a picture of the room taken from one point, which slides
across a large floor. A flat mirror, a polished floor or a still pool can do
better, because a flat surface reflects exactly what a camera mirrored in its
plane would see.

That is what this page does. Each frame the scene is drawn a second time
through the view's camera mirrored in the floor's plane, and that picture is
laid over the floor. The near plane of the mirrored camera is moved onto the
floor, so nothing below the floor is reflected up through it.

## Step 1: The floor

A dark, smooth floor. It keeps its own material: it is lit, shadowed and
textured as any floor would be, and the reflection goes on top.

{{code floor}}

## Step 2: Something to reflect

A red ball, a gold metal block and a tall blue post. The post is the easiest
to follow in the reflection as you orbit.

{{code objects}}

## Step 3: The reflector

A `PlanarReflectorNode` is the plane: it passes through the node's origin,
with its local +Y as the side the reflection is seen from. A camera below the
floor sees no reflection, as one under a pool sees none. `surfaces` are the
meshes that lie in the plane, here the floor. They are left out of the
reflection themselves, since they stand where the mirrored camera's clip
would cut them in half.

`reflectance` is how much is reflected looking straight down at the plane:
one for a mirror, which reflects everything at every angle, and about 0.02
for water, which reflects little looking down and nearly everything at a
grazing angle. `resolution` is the size of the reflection's picture as a
fraction of the view's, half by default, which is a quarter of the pixels.

{{code mirror}}

## Step 4: Switch it on

`RenderSettings.planarReflections` is off by default. With it off, the
reflector costs nothing. With it on, a pass called `planar reflections`
runs before the scene and draws the mirrored picture for every view that
sees the plane's front.

Switch **Planar reflections** off and on. Drag **Reflectance** down towards
0.02 and orbit to a low angle: the floor reflects little from above and
nearly everything near the horizon, as water does. Raise it to one for a
mirror. Lower **Resolution** and the reflection softens.

{{code switch}}

## Step 5: What the frame should show

With the switch on, the pass runs and the mirrored camera draws the three
objects that stand above the floor. With it off, the pass does not run.

{{code check}}

> **Note.** A reflection costs a second picture of the scene per view, drawn
> with the frame's lights, shadows and sky. Nothing inside it is reflected
> again, and particles and other contributors do not reach it.
