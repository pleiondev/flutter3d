# Flickering lights

A torch's flame and the light it casts have to agree, or a fire that dances
while its light stays flat reads as fake. `LightFixture` owns one brightness
number and drives both from it.

## Step 1: Make a fixture

`LightFixture` names the level light it drives and a `LightBehaviour`.
`FlameFlicker` is two unrelated sine waves plus a slow one, deliberately
computed from the clock rather than from randomness, so the same moment
looks the same after a reload.

{{code fixture}}

## Step 2: Step it and read its brightness

Each frame, the fixture is stepped like anything else in the simulation, and
its brightness drives both the light's intensity and the glow on the torch's
own material.

{{code step}}

Switch to "Pulse instead of flicker" and the fixture is rebuilt with
`PulseLight`, a slow smooth swell instead of a flame's jitter.

## Step 3: Turn it off

{{code toggle}}

A fixture that is switched off reports zero brightness on its very next
step, whichever behaviour it was running.
