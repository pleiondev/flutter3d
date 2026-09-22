# The cached shadow map

A lamp's shadow costs six pictures of the scene, one per face of a cube, and by
default that would be six pictures every frame. Most of what a lamp lights does not
move: walls, floors, pillars. Drawing those again on every frame buys nothing.

So the lamp's atlas comes in two halves. One holds the things marked static. It is
drawn once and kept. The other holds the things that move and is redrawn only where
something changed. The lighting shader reads both and keeps whichever occluder is nearer.

## Step 1: Mark what never moves

Two walls with `shadowIsStatic = true`. It is off by default, on purpose: a mover wrongly
marked static leaves its old shadow behind when it moves, while a static thing left
unmarked only costs a redraw.

{{code walls}}

## Step 2: Something that does move

A ball circling the lamp. It stays dynamic, so it is drawn into the moving half every
time its position changes, and the shadow of the walls does not have to be redrawn with it.

{{code orbit}}

{{code mover}}

## Step 3: Tell the cache when a caster changes

Flipping the flag by hand does not change what is already in the kept half. The page
calls `invalidateStaticShadows()` on the scene when you toggle **Walls are static**, and
the walls are then drawn again into whichever half they now belong to.

Try it: with the toggle off the walls move into the redrawn half, and with it on they are
baked once more. The picture should look the same either way. The difference is how much
work each frame does.

{{code invalidate}}

## Step 4: Look at the atlas

`showStaticShadowMap` swaps the scene for the kept half of the atlas, and
`showShadowMap` for the moving half. Each is a grid with six cube faces across and one
row per lamp. The static one holds the walls and never the ball. The moving one holds the
ball, which shifts from frame to frame, and leaves the walls out.

{{code atlas}}

> **Note.** Changing `casterFaces`, `depthPadding` or `cubeResolution` also forces the
> kept half to be drawn again, because they decide what a stored distance means. Biases
> and softness do not: they are read when the atlas is sampled.
