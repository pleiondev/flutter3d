# Lights in lumens and lux

`LightNode.intensity` is a plain number with no unit of its own. `Photometric`
fixes an exchange rate for it: an 800 lumen point lamp, the ordinary bulb
that replaced a sixty-watt incandescent, converts to an intensity of `1.0` at
a metre. Every other conversion follows from that by arithmetic, so a lamp
off a datasheet can be typed in directly instead of tuned by eye.

## Step 1: A sky in lux

A directional light has no position and no falloff, so its intensity is the
illuminance a facing surface reads, anywhere in the scene. Overcast daylight
is about ten thousand lux.

{{code directional}}

## Step 2: A lamp in lumens

A point lamp spreads its flux over the whole sphere around it, so
`Photometric.fromLumens` divides by `4π` before converting to intensity.

{{code point}}

## Step 3: Move the sliders

Both lights are recomputed every frame from whichever unit their slider is
in, so raising the lux slider is the same as raising the sun outside a
window.

{{code live}}

## Step 4: What round-trips

`Photometric.toLux` and `Photometric.toLumens` are the inverse of the two
conversions above. Feeding a light's intensity back through them should
return the exact number the slider set, and that is what this page checks.

{{code check}}
