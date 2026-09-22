# Directional, point and spot lights

Three of the engine's four light shapes leave from a single point in space,
which is what "punctual" means here: the direction to the light is one
vector, and the surface only has to answer one cosine. A directional light
has no position at all, a point light falls off with distance in every
direction, and a spot light is a point light narrowed into a cone.

## Step 1: A directional light

No position, no range, no falloff: a directional light lights every surface
that faces it the same way, wherever that surface stands in the scene.

{{code directional}}

## Step 2: A point light

`range` bounds how far a point light reaches. Past it, the light
contributes nothing at all, which is what lets a level with hundreds of
lamps only pay for the ones actually near a surface.

{{code point}}

## Step 3: A spot light

A spot light is a point light with two cone angles added: `innerConeAngle`
is where the light is at full strength, and `outerConeAngle` is where it
reaches zero. `SceneNode.lookAt` aims a spot exactly the way it aims a
camera, down the node's own local `-Z`.

{{code spot}}

## Step 4: Move the sliders

The point light's `range` and the spot's cone angle are read back into the
lights every frame, so the sliders change what each light actually does
rather than a copy of it.

{{code live}}

{{code check}}
