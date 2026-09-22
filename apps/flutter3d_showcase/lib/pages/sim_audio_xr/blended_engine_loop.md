# A blended engine loop

An engine's note is one or more recordings, each at a different rev range,
crossfaded by whatever number is driving them. A single stretched recording
sounds like a siren at the ends; `BlendedLoop` mixes a handful of loops
instead, weighted so the change from one to the next is not audible.

## Step 1: Bands, each centred on the value it was recorded at

`LoopBand.centre` is what a recording actually is: a loop taken at three
quarters of the revs has a centre of 0.75.

{{code bands}}

## Step 2: Drive it every frame

`update` takes the current value and mixes the bands' gains and playback
rates to match it.

{{code update}}

Move the slider and the mix shifts smoothly between the idle, mid and high
recordings.

## Step 3: Check the loudness stays level

{{code loudness}}

The weights are normalised, so the three bands' gains always add up to full
loudness, even sitting exactly between two of them — without that, the
middle of a crossfade would read as the engine cutting out.
