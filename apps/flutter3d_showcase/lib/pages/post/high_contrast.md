# High contrast

Some players cannot pick a monster out of a busy floor by its colour, or
cannot see the edge of a step against the floor in front of it. The
high-contrast look is an accommodation for them. It takes the texture out of
every surface, drains most of the colour out of the frame, draws a line at
every edge the geometry has, and then puts colour back only on the things a
game says matter, as a ring around each one.

It is off by default. A game switches it on when a player asks for it, which
`flutter3d_game` reads from the platform's own high-contrast setting with the
player's switch over it. This page sets it directly.

## Step 1: A level with too much going on

A tiled floor in two close greens and browns, and three crates painted three
different colours. This is the detail the look is there to remove: the tiles
are texture inside one surface, and the crates' paint says nothing about what
they are.

{{code level}}

## Step 2: Mark what the player has to find

`MeshNode.outlineColor` gives a node a role colour. Here a monster is red, a
pickup is yellow and the way out is green. The three balls are the same grey
underneath, so with the look off nothing tells them apart.

The colour is a display colour, as a swatch gives it, and not linear like a
material's tint: the ring is drawn on the finished picture, after the tone
map, so it comes out the colour the player picked. A mark is per mesh. A model
made of several meshes is marked by walking it.

{{code roles}}

## Step 3: Turn the look on

`RenderSettings.highContrast` takes a `HighContrastSettings`. `saturation` is
how much colour each pixel keeps, a quarter by default, and `contrast` pushes
light and dark apart around mid grey. `outlineWidth` is how far the edge line
reaches, in pixels. `roleWidth` is the ring around a marked node, and
`roleFill` lays a share of the same colour over the node itself, so a small
thing far away is still easy to find.

The flattening asks the surface buffer, not the picture, which neighbouring
pixels belong to the same surface. The mortar between two tiles is an edge in
colour but not in depth or facing, so it is averaged away, while the step
between floor and crate stays. The edge line works on how far depth bends,
not how far it steps, so a floor seen at a slant is not drawn as one solid
block of line.

Switch **High contrast** off and on. Then switch **Role outlines** off: the
three balls go back to being grey shapes among grey shapes. Drag
**Saturation** up to see how much colour the look normally takes away.

{{code look}}

## Step 4: What the frame should show

The look is a pass called `high contrast` on the finished picture. The rings
come from a mask drawn before it, `outline mask`, which runs only while the
look is on and some node is marked. With the look off neither pass runs, so
leaving marks set on a game's monsters costs nothing for a player who never
asks for the look.

{{code check}}

> **Note.** The look reads the surface buffer, so the frame loses its
> multisampling while it is on. A mark behind something the scene drew is
> dropped against the same buffer, so a monster is never ringed through a
> wall.
