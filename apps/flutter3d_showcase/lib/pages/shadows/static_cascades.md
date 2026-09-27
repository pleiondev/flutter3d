# Cascades that keep what stands still

The sun's shadow is an atlas of three tiles, one per cascade, and the near tiles follow
the camera. Drawn from nothing, every tile a camera moves has to draw every caster inside
it again, even when not one of them moved.

Since 0.8.0 each tile keys on its own matrix and on the casters its volume holds, so a
tile whose matrix and casters are unchanged is kept as it is. Casters marked
`shadowIsStatic` go further: they live in an atlas of their own, and each frame's tile
starts from a copy of it with only the things that move drawn on top. When the camera
walks, that static atlas is scrolled by whole texels and only the strips that came into
view are drawn.

## Step 1: A field that never moves

Sixty blocks in twelve columns and five rows, all sharing one mesh, all marked
`shadowIsStatic`. The flag is off by default: a mover wrongly marked static leaves its
old shadow behind, while a static block left unmarked only costs a redraw.

{{code field}}

## Step 2: One thing that does move

A ball rolls back and forth in the gap between two columns. It stays dynamic, so it is
drawn into the frame's tile over the copy of the blocks, and the blocks are not drawn
with it.

{{code ball}}

{{code roll}}

The ball's path stays inside the field. The last cascade covers every caster and is
fitted to their bounds, so a ball that wandered outside them would change that tile's
matrix, and the whole tile would be drawn again.

## Step 3: A sun and a walk

The sun is a directional light, which asks for a shadow map by default. The ground
receives shadows but casts none: a ground that cast would lie in every tile, and every
tile would then hold something to redraw.

{{code sun}}

The camera slides sideways and back. A cascade's centre is snapped to whole texels in
the light's frame, so as the camera walks the near tiles move by whole texels, which is
what lets the static atlas be scrolled instead of drawn again.

{{code walk}}

{{code settings}}

Switch on **Show the sun's atlas** to see the three tiles side by side. With the blocks
static, what you see is the copy of the kept blocks with the ball drawn over it.

## Step 4: Flip the flag

Switch **Blocks are static** off and the blocks join the ball in the frame's own tiles.
The picture looks the same. The difference is the work: every tile the camera moves now
draws every block inside it, where before it drew the strips at its edge.

A tile's key lists its casters by which half they belong to, so flipping the flag is
noticed on the next frame without anything else to call.

{{code flag}}

## Step 5: What the frame reports

The page has no counter on screen, but the frame keeps one. `FrameResult.passes` has an
entry named `directional shadows`, and its `drawCalls` counts every draw into the sun's
atlas: the casters, the copies of the static tiles, and the draws that blank a tile
before it is drawn again.

{{code count}}

The page's own check reads it twice. The first frame makes at least one draw per block,
since the last cascade holds all sixty. Then the ball moves a little with the camera
still, and the next frame may draw no more than a copy and the ball in each cascade.

{{code check}}

> **Note.** The engine's changelog measures a walk over sixty static blocks at a dozen
> casters a frame, where the same walk used to draw sixty-eight.
