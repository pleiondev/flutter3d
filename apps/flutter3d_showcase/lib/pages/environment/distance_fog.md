# Distance fog

Fog makes things fade as they get farther from the eye. It gives a long view its
depth, and it hides the place where the world ends, because everything out
there has already turned into the fog colour.

## Step 1: Something to look down

Twelve pillars in two rows, receding from you. Rows of identical things are the
easiest way to see fog: the same pillar is drawn again and again, farther each
time, and only the distance changes how it looks.

{{code pillars}}

## Step 2: A background to fade into

Fog does not touch the background. If the far pillars faded to grey against a
blue sky, they would look like ghosts. So the page draws a procedural sky, and
the next step reads the fog colour from it.

{{code sky}}

## Step 3: Turn the fog on

`FogSettings` has two values this page sets. `density` is how quickly things
disappear, per metre of distance. It is exponential, so there is no line where
fog begins: it is thin near you and thickens smoothly. Zero means no fog.
`color` is what everything turns into.

A third, `heightFalloff`, is left at its default of 0.05 per metre, so the fog
lies on the ground: it halves every fourteen metres of height, and the tops of
the pillars are a little clearer than their feet. `heightFalloff: 0.0` gives
fog of one thickness at every height.

Here the colour is asked of the sky, looking straight toward the horizon, so the
far end of the view and the sky meet without a seam. Drag **Density** up and the
pillars vanish one by one from the back. Switch **Fog takes the sky colour** off
and the far pillars turn red against a blue sky, which is what a fog that
ignores its background looks like.

{{code fog}}

> **Note.** The fog colour is linear light, like the sky colours, and is
> blended before the tone curve. A dark grey default is used when you give none.
