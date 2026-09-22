# Soft shadows

A real light has a size, so the edge of its shadow is not a line. Right where a
shadow starts, at the foot of the thing casting it, the edge is sharp. The further the
shadow travels, the wider the blurred band around its edge gets. That band is the
penumbra, and by default the engine draws the same narrow edge everywhere.

## Step 1: Something that casts near and far

A pole standing on the ground and a thin slab held a metre and a half above it. The
foot of the pole touches the ground, so its shadow should start sharp. The slab hangs
in the air, so its whole shadow has travelled and should be soft.

{{code casters}}

## Step 2: A sun and a lamp

One directional light and one point light, both in the scene. The page lets one of
them cast at a time, so you can compare. The lamp has a `range` because a point light
fades out; the sun does not.

{{code lights}}

## Step 3: Give the light a size

`directionalLightRadius` is the sun's apparent size. At zero, the shadow uses the fixed
narrow edge every earlier frame had. Above zero the renderer looks for what is
blocking each shadowed point and widens the edge by how far away the blocker is. Drag
**Sun size** up and watch the slab's shadow blur while the foot of the pole stays crisp.

`pointLightRadius` does the same for the lamp, in metres. Switch **Light** to Lamp and
move **Lamp size**. The change is gentler here, because the lamp's shadow map is small.

{{code settings}}

> **Note.** The sun's number is in the units of the shadow map's own depth, so it depends
> on the scene. Pick it by looking at the picture, not from a table.
