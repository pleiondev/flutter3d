# Alpha modes

A material can be see-through, and there is more than one way to decide what that
means. `MaterialAlphaMode` has four answers: `opaque`, `mask`, `blend` and `hashed`. This
page draws the same soft disc four times, one per mode, in front of a blue wall,
from left to right in that order.

## Step 1: A soft disc

The texture is white with an alpha that is full at the centre and fades to nothing
at the rim. Every mode reads that alpha, multiplied by the alpha of the material's
`baseColor`, and only what they do with it differs.

{{code texture}}

## Step 2: Four materials, one for each mode

The four materials are identical except for `alphaMode`. `opaque` ignores alpha
altogether, so the leftmost panel stays a solid square. `mask` keeps a pixel or
drops it against `alphaCutoff`. `blend` mixes the panel with what is behind it.
`hashed` keeps a share of the pixels equal to the opacity, chosen by a noise
pattern fixed to world position.

{{code materials}}

## Step 3: Stand them up

The panels are flat planes turned to face the camera and laid out in a row. The
blue wall behind them is what makes blending and cutting visible.

{{code panels}}

> **Note.** `blend` has to draw after everything opaque and be sorted by distance,
> which costs a sort every frame. `hashed` is drawn with the opaque surfaces and
> needs no sort, at the price of visible noise.

## Step 4: Move the numbers

Drag Alpha cutoff and the second panel's edge moves in and out: it is a hard
circle, because a pixel is either above the cutoff or not. Drag Opacity and watch
the fourth panel: its pixels thin out, and from a distance they average to that
opacity.

Turn on Double sided and drag the view round to the back of the panels. With it
off, the back of a surface is culled and you see straight through; with it on,
both faces draw.

{{code live}}
