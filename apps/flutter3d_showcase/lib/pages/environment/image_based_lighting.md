# Image-based lighting

A lamp lights a surface from one direction. The real world lights it from
everywhere at once: the sky above, the ground below, a bright window to one
side. Image-based lighting does the same with a picture. The picture is a cube
map of the surroundings, and each surface picks its light out of it.

There is no light in this scene at all. Everything you see comes from the cube.

## Step 1: Make the environment

`EnvironmentMap.fromSky` turns a `SkySettings` into a cube map, and
`EnvironmentMap.fromPanorama` does the same from an ordinary 360 degree picture.
The page builds both, so you can switch between them. The panorama here is
drawn in code, 64 by 32 pixels: a blue sky, a brown floor and one bright window.

Both calls do a second thing that matters. A rough surface does not reflect one
direction, it gathers a wide cone of light, so the cube is blurred several times,
sharper for smooth surfaces and softer for rough ones, and the blurred copies
are stored as the mip levels of the same cube.

{{code environments}}

## Step 2: Spheres of every roughness

Five metal spheres, from nearly a mirror on the left to fully rough on the
right. They share a mesh and differ only in `roughness`. Because each one
reads the level of the cube that matches its roughness, you can see the
blurring from step 1 laid out in a row: the left sphere holds a clear picture of
the sky and the window, the right one only a smear of colour.

Drag **Metallic** down and the spheres turn from metal into plastic, which
reflects less and shows more of its own colour.

{{code balls}}

## Step 3: Give the scene the cube

Two fields on the scene do it. `environment` is the cube and
`environmentLevels` says how many blurred levels follow the base. The
`ambientIntensity` that used to scale a flat ambient colour now scales the
cube, which is what the **Strength** slider changes. Switch **Environment on**
off and the scene falls back to the flat ambient, which is nearly black here.

{{code use}}

> **Note.** The cube is eight bits per channel, so a sun far brighter than the
> sky around it is clamped to white before it is stored. It reflects less than
> a real sun would.
