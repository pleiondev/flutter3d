# Ambient light

`Scene.ambientColor` and `Scene.ambientIntensity` are the flat term a
surface falls back to wherever no direct light reaches it. They are what
keeps the far side of a lit object from going pure black, and the only
light source in a scene that otherwise has none at all.

## Step 1: One light, and a side it never reaches

A single key light from one side leaves the far side of the ball with
nothing but the ambient term to read by. That is what makes the effect
visible: a scene lit evenly from everywhere would show nothing when the
ambient term changed.

{{code ambient}}

## Step 2: Move the slider

`ambientIntensity` is read back into the scene every frame, so raising it
lifts exactly the shadowed side and leaves the lit side alone.

{{code live}}

## Step 3: What this page checks

The test cannot compare two pictures, so it checks the wiring instead: the
scene's ambient intensity is the number the slider set, and there really is
only one direct light, which is what leaves a side for the ambient term to
fill in the first place.

{{code check}}
