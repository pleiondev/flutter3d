# Shadow quality

A shadow is a picture of the scene taken from the light, called a shadow map. Every
choice about how it looks comes down to a few numbers: how big that picture is, how
much room it leaves for error, how dark it paints and how far from you it is fitted.
This page keeps them on four sliders so you can watch each one.

## Step 1: A ground to catch it

A shadow needs a surface to land on. The ground is a flat `PlaneShape`, fourteen
metres each way, in one plain stone material.

{{code ground}}

## Step 2: Two things that cast

A tall column and a ball, both in clay. The column has straight edges and the ball
has curved ones, so between them you can see what each setting does to both kinds of
outline.

{{code casters}}

## Step 3: A sun that asks for a shadow

A light casts nothing unless it asks. `castsShadow: true` tells the renderer to draw
the scene from the sun's side and keep the result.

{{code sun}}

## Step 4: Turn the four numbers

`ShadowSettings` holds them. The page starts at the smallest map, 256 pixels, so the
edges are blocky. Raise **Map size** and watch the staircase on the edge of the
column's shadow shrink.

`resolution` is the size of one map. `bias` is how far a surface has to be behind the
recorded depth before it counts as shadowed. Drop it to zero and the ground fills with
stripes, because the ground starts shadowing itself. Raise it far enough and the
shadow slides away from the column's foot.

`strength` is how dark a full shadow gets. `viewDistance` is how far from the viewer the
near map is fitted: with two cascades, the near one covers only that stretch and the far
one takes the rest. Pull **Distance** down and the near map shrinks around you, so the
same pixels cover less ground and the shadows near you get sharper.

{{code settings}}

> **Tip.** Change one slider at a time. Bias and map size trade against each other: a
> bigger map usually lets you use a smaller bias.
