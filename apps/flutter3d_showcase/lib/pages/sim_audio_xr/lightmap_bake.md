# Baking a lightmap

Direct light and its shadows stay dynamic, so a torch can flicker and a door
can open. The light that does not move is a wall lighting the floor next to
it, and baking that once is cheaper than computing it every frame. Baking a
lightmap is two steps: plan where each face lives in the atlas, then gather
the light into it.

## Step 1: A small level

A floor and a wall, meeting at a corner, with a point light above them.

{{code level}}

## Step 2: Plan the atlas

`LightmapLayout.plan` unwraps every visible brush face onto a planar atlas,
purely from the level and a chosen density. The baker and the level's own
geometry agree on where each face sits without a separate table.

{{code layout}}

## Step 3: Bake the light

`LightmapBaker.bake` gathers the direct light and its bounces into the
planned atlas, seeded so two bakes of the same level are the same bytes.

{{code bake}}

The corner where the wall meets the floor picks up light from both, so the
map is not left entirely black.

## Step 4: See what it baked

The page shows the atlas itself: each texel of every face of the closet, as
bright as the light that reaches it. Slide the light along the closet and the
bright patch on the floor follows it; take the bounces to zero and the wall
loses what the floor was lending it; lower the samples and the noise shows.
Each change is a whole new bake, made when you let go of the slider.

{{code live}}
