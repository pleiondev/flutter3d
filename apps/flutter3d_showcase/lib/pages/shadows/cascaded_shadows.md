# Cascaded shadows

One shadow map cannot be sharp under your feet and still cover a field a hundred
metres long: there are only so many pixels in it. A cascaded shadow splits the
view into a few slices, near to far, and gives each its own map. The near slice is
small and sharp, the far one large and soft.

## Step 1: A place to cast on

Shadows need a surface to fall on. The floor is a flat `PlaneShape`, eighty
metres each way, in one plain stone material, so the far pillars have somewhere
to put their shadow too.

{{code floor}}

## Step 2: Things that cast

Ten pillars in a row, from your feet toward the horizon. They share one mesh: a
mesh is uploaded once and any number of nodes can draw it.

{{code pillars}}

## Step 3: A sun that asks for a shadow

A light casts no shadow unless it says so. `castsShadow: true` asks the renderer to
draw the scene from the sun's side; only a directional light is cascaded.

{{code sun}}

> **Warning.** A light asking for a shadow is a request, not a promise: the renderer
> shadows one directional light and a few point lights, and reports in
> `FrameResult.shadowsDenied` when it had to refuse.

## Step 4: Choose the cascades

`ShadowSettings` is where the split is decided. `cascades` is how many maps,
`cascadeSplit` how strongly the near ones are made smaller than the far ones and
`viewDistance` how far the last one reaches. Drag the sliders and watch the edge
of the near shadows.

{{code settings}}
