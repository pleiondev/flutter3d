# The six lighting models

A lighting model decides how a surface answers light. The engine ships six, and a
material picks one by name. This page puts the same orange colour under each of
them so you can see what the choice changes.

Read the spheres in reading order: Unlit, Lambert and Blinn-Phong on the top row,
then PBR, Toon and Normals below.

## Step 1: Take one material per model

`LightingModel.builtIn` lists the six in the order a picker would show them. The
loop makes one `Material` for each, with the same colour and roughness, so the only
thing that differs between the spheres is the model.

{{code models}}

Each model is a fragment shader compiled ahead of time. Choosing a model is
choosing a shader, and the renderer keeps one pipeline for each.

## Step 2: Lay them out in a grid

One `DeviceMesh` is uploaded once and shared by six `MeshNode`s. Each node pairs it
with its own material and moves to a cell of a three by two grid.

{{code row}}

## Step 3: Add a light

Without a light a lit model is black. A single directional `LightNode` is enough
here. Unlit ignores it and draws the flat colour, Normals ignores it and paints the
direction each point faces, and the other four use it.

{{code light}}

Drag the view around. Unlit and Normals look the same from every side, while the
lit spheres change as you move.

## Step 4: Move the sliders

Roughness is read by Blinn-Phong, PBR and Toon, and each reads it differently.
Blinn-Phong turns it into the sharpness of the highlight, PBR spreads the highlight
over more of the sphere, and Toon uses it to choose how many bands of shade to draw.
Lambert has no highlight and does not read it, so its sphere stays put.

{{code live}}

> **Note.** Setting a field is enough. The next frame draws with the new value and
> nothing is rebuilt.
