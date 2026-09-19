# The six lighting models

A lighting model is the recipe a surface uses to answer light. The engine ships
six of them, and each is one pre-built shader. This page draws the same sphere
six times, once per model, so you can see what each recipe does with the same
colour and the same sun.

## Step 1: One material per model

`LightingModel.builtIn` is the list of everything that came with the engine, in
the order a picker would show it: unlit, Lambert, Blinn-Phong, PBR, toon and
normals. A `Material` names its model in `lighting`, and that is the only change
between the six materials here.

{{code models}}

> **Note.** The list is not closed. An application that builds its own shader
> bundle can describe a seventh model and use it the same way.

## Step 2: Put them on a grid

One sphere mesh is uploaded once and six nodes draw it, each with its own
material. Two rows of three keep every model in view at the same time.

{{code grid}}

## Step 3: Light the scene

A single directional light is enough. Look at the top left sphere first: the unlit
model ignores the sun and shows its plain colour. The last sphere, the normals
model, ignores it too and paints the surface direction as colour.

{{code light}}

## Step 4: Turn the two sliders

Drag Roughness. Lambert is purely diffuse, so it does not move at all. Blinn-Phong
and PBR change their highlight, and toon keeps its hard bands. Drag Sun to zero
and only the two models that do not need a light stay visible.

{{code live}}

Every change here is a plain field write. Nothing is rebuilt, because each model
was a pipeline the first frame already linked.
