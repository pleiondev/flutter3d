# X-ray silhouettes

In a game you sometimes want to see through a wall: an enemy behind a door, a
teammate behind a crate. An x-ray silhouette paints the outline of what is
hidden, in a flat colour, over whatever hides it. The parts you can already see
keep their normal shading.

## Step 1: Choose who gets a silhouette

Every node has a `layerMask`, a set of bits. The x-ray setting names some bits,
and any node that shares one of them is treated as watched. The default mask is
1, so this page uses a different bit and keeps the default as well.

{{code layer}}

## Step 2: Hide something

The monster stands two metres behind the wall, and its `layerMask` carries the
watched bit. Nothing else about it is special: it is an ordinary lit capsule.
Without x-ray the wall simply hides it.

{{code hidden}}

## Step 3: Turn it on

`XraySettings` takes the mask and, if you like, a colour. The colour is in linear
light, before exposure. A mask of 0 means off, so the switch beside the picture
only changes that number. Turn X-ray on and an orange capsule shape appears on the
face of the wall. Drag the view sideways until the monster steps out from behind
the wall: the part in the open is lit as usual and only the hidden part is
painted.

{{code settings}}

Only opaque things hide anything. A monster behind glass can be seen through the
glass, so it gets no silhouette.

## Step 4: See what it cost

Each watched node is drawn twice more at the end of the scene pass. The first
draw marks the stencil where the node is visible. The second paints the flat
colour where the depth test says something is in front and the stencil says
the node is not showing. The stencil is what keeps the visible half of a
half-hidden monster lit.

Because it needs a stencil buffer, a device without one draws no silhouettes and
the frame is the frame you would have had without the setting. The page checks
the number of draws in the scene pass for both cases.

{{code draws}}
