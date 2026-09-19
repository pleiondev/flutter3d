# Generated tangents

A normal map is read in the surface's own tangent space, not in world space.
Without a tangent that follows the surface, every point samples the map along
the same fixed direction, wherever the surface itself is facing.

## Step 1: Start from a mesh with no tangent

The torus is built without asking for a tangent attribute. This is the shape a
format with no tangent record, such as OBJ, would hand back.

{{code undressed}}

## Step 2: Two ways to add one back

`convertedTo` fills a missing tangent with the same constant value at every
vertex, because that is the only safe default for an attribute it knows
nothing about. `withGeneratedTangents` instead derives a tangent per vertex
from the UV parametrization, so it turns with the surface.

{{code compare}}

## Step 3: Light both with the same tilted normal map

The normal map here is one solid, tilted direction, encoded as a single
colour. On the torus with generated tangents, that tilt follows the tube
around the ring, so the highlight curves with the surface. On the flat-tangent
copy the tilt stays locked to one direction in space, and the highlight looks
wrong wherever the tube has turned away from it.

{{code bump}}

## Step 4: Check the tangents actually vary

The page reads the tangent attribute back out of both meshes. The flat copy
must hold the same value at every vertex; the generated copy must not.

{{code check}}
