# Tone-map curves

The renderer works in light that has no ceiling: a lamp can be four or forty times brighter than white. A display has a ceiling. A tone-map curve is the rule that squeezes one into the other, and the choice of rule changes how a picture feels. This page has the engine's curves on one scene, a display transform it bakes itself, and three lamps that are far brighter than white.

## Step 1: Something brighter than white

Three small emissive spheres in the primary colours, each with an `emissiveStrength` of six. On the way to the screen these values have to be brought below 1.0. How that happens is what you are about to compare.

{{code lamps}}

## Step 2: Pick a curve

`RenderSettings.tonemapCurve` takes one of the `TonemapCurve` values. Open the Curve choice and step through them while you watch the lamps and the lit side of the shapes.

`neutral` leaves the middle of the picture where the materials put it. `aces` gives a filmic shoulder and heavier midtones. `agx` keeps a gradient inside very bright saturated colour, which you can see on the blue lamp, and keeps its hue while it walks towards white; `agxFull` is the same transform under its older name. `reinhard` touches little except the highlights. `aces2` is the ACES 2.0 SDR tonescale at 100 nits with the hue held: the tonescale alone, without the gamut mapping of the full ACES 2.0 output transform. It is not a formula in the shader but a table the engine ships, read the way Step 4 reads one of your own.

{{code curve}}

## Step 3: Change how much light goes in

`exposure` is a multiplier applied before the curve. Drag Exposure up and more of the picture climbs into the part of the curve that flattens, so the lamps lose their colour first. Drag it down and the whole picture darkens, while the curve still keeps the lamps from clipping.

{{code exposure}}

## Step 4: Bake a display transform of your own

A display transform is a table in place of the curve. `LookSettings.displayTransform` takes a `DisplayTransform`: a float texture in the colour table's strip shape and the number of entries per axis. The input is scene light, looked up through a log2 shaper that runs from ten stops below mid grey to ten stops above it, and the output is display-linear light. Anything past the last entry clamps to it.

This page bakes a small one, seventeen entries per axis, in Dart. Its curve is Reinhard on the brightest channel, with the colour scaled along so the hue holds. It has no path to white, so the lamps stay red, green and blue however far you push Exposure. `aces2` desaturates what it compresses and takes the lamps towards white instead. That is the kind of decision a display transform holds.

{{code table}}

The table has to be a float format the device samples with filtering. The strip goes up as half floats, the same format as the table the engine ships for `aces2`.

{{code upload}}

Set **Display transform** to `page table`. When one is set it wins over whichever curve is chosen, so the Curve choice stops changing the picture until you set it back to `none`. `RenderSettings.tonemap` off still turns it off along with the curve. A table baked by another tool, the ACES 2.0 reference transform through OCIO for one, goes in the same way.

{{code display}}

> **Note.** `RenderSettings.outputTransform` is `OutputTransform.sdr` by default, and that is what this page draws with. `OutputTransform.extendedSrgb`, on a device that offers HDR output, draws the frame exposed but with neither the curve nor the table, in extended sRGB where a highlight can go past white. Everywhere else it draws the SDR frame byte for byte, so on a screen without HDR a switch for it would change nothing, and the page has none.

> **Note.** None of these curves is the correct one. The default is `neutral` because a model looks in the viewer the way its author saw it. The others are a look you choose.
