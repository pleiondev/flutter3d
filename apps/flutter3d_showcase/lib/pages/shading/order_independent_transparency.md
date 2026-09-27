# Transparency without sorting

A blended surface is drawn over whatever is already in the picture, so see-through
things have to be drawn back to front. The renderer sorts them by distance, one sort key
per draw. That works until two panes pass through each other: each one is partly in
front of the other, and whichever goes first is wrong for part of its pixels.

Weighted blended transparency drops the sort. Every see-through draw adds its colour into
a buffer, weighted by its depth and its alpha, in any order, and one last pass lays the
weighted average over the scene.

## Step 1: Panes that no order can fix

Five unlit panes with `MaterialAlphaMode.blend`. Three stand one behind another; the
yellow and the purple ones are turned in opposite directions about the same spot, so
they cut through each other.

{{code panes}}

## Step 2: Something behind them

A grey wall, opaque, so there is a scene for the transparent half to be laid over.

{{code wall}}

## Step 3: Pick how they are composited

`RenderSettings.transparency` is `TransparencyMode.sorted` by default, which is how every
frame was drawn before the other mode existed. `TransparencyMode.weightedBlended` draws
the transparent half into two targets of its own: one sums the weighted colours, the
other multiplies up how much of the scene still shows through. A full-screen pass then
resolves the two over the scene.

{{code settings}}

Switch **Transparency** to **Sorted** and look at the yellow and purple panes. They share
a centre, so the sort puts one of them first everywhere, and on one side of the crossing
the pane that stands behind is drawn over the one in front. Drag the view round and that
side stays wrong. Switch back to **Weighted blended** and both sides of the crossing are
treated alike.

> **Note.** The price is accuracy. Sorted, the nearer pane covers the one behind it;
> weighted, the nearer one only counts for more, so a stack of strongly coloured glass
> looks more mixed than it would sorted. The mode also costs two targets the size of the
> scene, keeps the depth buffer across passes, and turns multisampling off in the scene
> pass. A device without independent blending draws the transparent list twice, once
> for each target.
