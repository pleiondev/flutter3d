# One bounce of diffuse light

A sky environment answers one question about indirect light: what does the
sky look like from here. It says nothing about the room. A red wall lit by a
white lamp should tint the white wall facing it, and an environment map has
no way to know the red wall is even there. An irradiance field is a grid of
probes that do know: each one is filled by casting rays out from it and
recording what colour comes back.

## Step 1: Lay out the grid

`IrradianceField` divides a box into cells, with a probe at each corner. Two
probes on every axis is the smallest field that has a cell at all.

{{code field}}

## Step 2: Fill it from the scene

`gather` casts a few dozen rays from every probe, finds what each one hits,
and asks that surface's own colour and the scene's lights what light comes
back. One bounce: what a ray finds is a surface lit directly by a lamp, not
a surface lit by another bounce. A room lit only by light that has already
bounced twice stays dark.

{{code gather}}

This is a bake, not a per-frame cost. It runs once, when the scene is built,
and the field is read many times after that.

## Step 3: Turn it on and dial the strength

A scene reads at most one field at a time, through `Scene.irradianceField`.
Turning it off falls back to whatever ambient light the scene already had.

{{code live}}

> **Note.** The field only sees the room it was baked in. Move the wall
> after gathering and the probes still answer for where the wall used to
> be, because nothing here reruns automatically.

Toggle **Field on** and the room loses its red tint on the side facing the
wall; drag **Ambient strength** and the tint scales with it, the same knob
a flat ambient uses.
