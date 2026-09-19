# Tone-map curves

The renderer works in light that has no ceiling: a lamp can be four or forty times brighter than white. A display has a ceiling. A tone-map curve is the rule that squeezes one into the other, and the choice of rule changes how a picture feels. This page has five of them on one scene, and three lamps that are far brighter than white.

## Step 1: Something brighter than white

Three small emissive spheres in the primary colours, each with an `emissiveStrength` of six. On the way to the screen these values have to be brought below 1.0. How that happens is what you are about to compare.

{{code lamps}}

## Step 2: Pick a curve

`RenderSettings.tonemapCurve` takes one of the five `TonemapCurve` values. Open the Curve choice and step through them while you watch the lamps and the lit side of the shapes.

`neutral` leaves the middle of the picture where the materials put it. `aces` gives a filmic shoulder and heavier midtones. `agx` and `agxFull` keep a gradient inside very bright saturated colour, which you can see on the blue lamp, and `agxFull` also keeps the hue where the plain curve loses it. `reinhard` touches little except the highlights.

{{code curve}}

## Step 3: Change how much light goes in

`exposure` is a multiplier applied before the curve. Drag Exposure up and more of the picture climbs into the part of the curve that flattens, so the lamps lose their colour first. Drag it down and the whole picture darkens, while the curve still keeps the lamps from clipping.

{{code exposure}}

> **Note.** None of these curves is the correct one. The default is `neutral` because a model looks in the viewer the way its author saw it. The others are a look you choose.
