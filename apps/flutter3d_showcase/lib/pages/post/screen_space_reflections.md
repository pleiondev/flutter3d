# Screen-space reflections

A mirror needs to know what is behind the camera, and a renderer only has what
is in front of it. Screen-space reflections cheat around that: for a pixel on a
polished surface, a ray is marched away from the camera and bounced off the
surface's normal, stepping through the picture the scene pass already drew.
Where it lands is what shows in the reflection.

## Step 1: Something polished to reflect in

The floor is one slab, and `roughness` decides how sharp the reflection is. The
shader fades reflections out between a roughness of 0.18 and 0.45, so anything
above that is treated as too rough to reflect at all.

{{code floor}}

## Step 2: Something worth reflecting

The reflection needs a subject bright enough to read clearly against the floor.
An emissive cube standing on the floor is the only thing this scene has to
bounce.

{{code beacon}}

## Step 3: March the ray

`ReflectionSettings.enabled` turns the pass on. `intensity` scales how much of
what the march finds is added back over the floor's own shading.

{{code settings}}

Drag Roughness up past 0.45 and the reflection under the cube disappears,
because the shader has decided the surface is no longer polished enough to
carry one. Drag it back down and the cube's warm colour returns to the floor.
Drag Intensity to zero and the reflection fades to nothing without touching
the floor's own light.

> **Warning.** The march can only find what the scene pass already drew. A
> shape only visible from behind the camera, or hidden behind something else
> in the picture, has no reflection, exactly the way a real mirror has no
> reflection of what is behind it either.

## Step 4: Confirm it ran

The frame lists every pass it drew. The page's own check looks for
`reflections` there.

{{code ran}}
