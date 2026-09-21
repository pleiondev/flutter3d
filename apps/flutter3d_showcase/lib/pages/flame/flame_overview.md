# The two layers, side by side

`Flutter3dFlameWidget` puts a Flame `GameWidget` and a flutter3d `SceneSurface`
in one `Stack`, Flame on top. Before any of this category's own bridges exist,
that composited widget already draws two layers — nothing here connects them
yet, on purpose: this page is the starting point every other page in
`flame` adds one mechanism to.

## Step 1: Flame's own layer

A Flame game is built out of components, and the plainest of them is a
`PositionComponent`. It has a position, and nothing else here has ever heard
of flutter3d.

{{code flame-layer}}

## Step 2: flutter3d's own layer

flutter3d's own layer is a cube, sitting at a spot of its own. Nothing here
has heard of Flame either.

{{code flutter3d-layer}}

## Step 3: Nothing links them

Advancing the Flame shape by one tick does not move it towards the cube, and
placing the cube never touched the Flame shape. Two engines, two layers, and
the seam between them is empty space until a page in this category fills it.

{{code unconnected}}

The Flame shape stayed exactly where it started while the cube sat at its own
position on the other side of the origin — the two layers this widget draws
never exchanged a single number.

## Step 4: Watch both run

On the page, the orange square is a Flame component that Flame's own game
slides across the top; the cube is a flutter3d node that the scene turns. Both
run at once, in one `Stack`, and neither reads the other. The game and the
scene are built once and kept: the widget is rebuilt every frame, and a game
made afresh each time would restart before it drew anything.

{{code live}}
