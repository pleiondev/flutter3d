# PBR metal and rough

A physically based material is described by three things you can feel: what colour
it is, how metallic it is and how rough. This page builds a ball out of them and
lets you change all three while it draws.

## Step 1: Make the material

A `Material` says how a surface answers light. `LightingModel.pbr` picks the
physically based shader; `metallic` and `roughness` are the two numbers it needs,
both from 0 to 1.

{{code material}}

> **Note.** `metallic` is close to a switch: real surfaces are either metal or
> not, and the values between are for the edge of a worn paint.

## Step 2: Give it a shape

A material draws nothing until it is on a mesh. `SphereShape` builds the mesh as
plain data, `DeviceMesh.upload` puts it on the device you are drawing with, and
`MeshNode` pairs the mesh with the material so the scene can hold it.

{{code mesh}}

## Step 3: Point a light at it

Without a light a lit material is black. A `LightNode` is a directional light
by default, a sun: its position does not matter, only which way it faces.
`setLocalForward` turns it.

{{code light}}

## Step 4: Change it while it runs

A material's numbers are ordinary fields. Setting them is enough: the next
frame draws with the new values, and nothing has to be rebuilt.

{{code live}}

The sliders beside the ball do exactly this. The rest of the page is the source,
in the third tab, and there is nothing in it that these four steps have not
shown.
