# Lights in lumens and lux

`LightNode.intensity` is in photometric units: lux for a directional light,
candela for a point, spot or area light. A lamp off a datasheet is typed in
as it is rated instead of tuned by eye, and `Photometric.fromLumens` turns a
box's lumens into candela. The camera's exposure then turns those absolute
values into a picture.

## Step 1: A sky in lux

A directional light has no position and no falloff, so its intensity is the
illuminance a facing surface reads, anywhere in the scene. Overcast daylight
is about ten thousand lux.

{{code directional}}

## Step 2: A lamp in lumens

A point lamp spreads its flux over the whole sphere around it, so
`Photometric.fromLumens` divides by `4π`: an 800 lumen bulb is about 64
candela.

{{code point}}

## Step 3: Expose for the light

Ten thousand lux and sixty-four candela are real amounts of light, so the
camera is set as it would be outdoors on an overcast day: metered for the
sky, about EV100 12. Under that sky the bulb barely shows, as a bulb does in
daylight; pull the sky slider down to a few hundred lux to see it.

{{code exposure}}

## Step 4: Move the sliders

Both lights are recomputed every frame from whichever unit their slider is
in, so raising the lux slider is the same as raising the sun outside a
window.

{{code live}}

## Step 5: What round-trips

The sky's intensity is its lux as it was typed, and `Photometric.toLumens`
is the inverse of `fromLumens`. Reading the lights back should return the
exact numbers the sliders set, and that is what this page checks.

{{code check}}
