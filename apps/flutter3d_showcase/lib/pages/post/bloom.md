# Bloom and halation

A display cannot show anything brighter than white, but a scene can hold light that is ten times brighter than that. Bloom takes the part above a threshold and lets it spill over the edges of whatever emits it, the way a bright lamp does in a camera. This page has one lamp that is far brighter than white, and four sliders that decide how it glows.

## Step 1: A light brighter than the display

The lamp is a small sphere whose `emissive` colour is multiplied by an `emissiveStrength` of nine. Nothing in the scene lights it: it emits nine times white on its own. Without bloom it would look like a flat pale disc, because everything above 1.0 is cut off at white.

{{code lamp}}

## Step 2: Choose what glows

`BloomSettings` is one field of `RenderSettings`, and bloom is on by default. `threshold` is the brightness where the glow starts. At 1.0 only the lamp qualifies, because everything else in the scene is darker than white. Drag Threshold down towards 0 and the floor and the shapes start to glow too.

`intensity` is how much of the glow is added back. Drag Intensity to zero and the pass switches itself off, and the frame stops listing it.

{{code glow}}

## Step 3: Set how far it reaches

`levels` is how many times the picture is halved on the way to a blur. Each halving doubles how far the glow spreads, so this is the radius control. Drag Reach from 1 to 7 and watch the halo around the lamp grow from a tight ring to a wide haze.

{{code reach}}

## Step 4: Warm the halo

At `halation` 0 the glow is the colour of the lamp. Raise Halation and only the wide outer part of the halo turns red, while the tight core keeps the colour of the highlight. That is the warm fringe you see around lights on film.

{{code halation}}

> **Tip.** If you turn Threshold up past the lamp's brightness the halo disappears, because no pixel is bright enough to feed it.
