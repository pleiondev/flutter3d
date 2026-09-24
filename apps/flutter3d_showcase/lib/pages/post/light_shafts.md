# Light shafts

The cheap way to fake a light shaft takes bright pixels on screen and streaks
them away from the sun, and it needs the sun in the picture to do it. This
page's effect is a different thing: it marches each view ray and asks the
sun's own shadow map whether that point in the air is lit. A beam through a
doorway comes out shaped like the doorway, and the sun does not have to be
anywhere in frame.

## Step 1: Something to cast a shape

Two pillars and a lintel make a doorway. Nothing about them is special, they
are ordinary stone.

{{code doorway}}

## Step 2: A sun that casts a shadow

Light shafts read the shadow map, so there has to be one. A directional light
that does not ask for a shadow gives the march nothing to sample, and the
pass draws no shafts at all rather than failing.

{{code sun}}

## Step 3: Turn the march on

`LightShaftSettings.enabled` runs it, `strength` is how thick the air is (a
density per metre: 0.005 is a clear day's haze, a few hundredths a dusty
room), `anisotropy` is which way it scatters, and `distance` is how far along
each ray the march reaches before it gives up. The light itself is the sun's:
its colour and intensity are what the air scatters. Walk around the doorway
while the app is running and the beam keeps the shape of the gap between the
pillars from every angle, because it is reading actual occlusion rather than a
screen-space streak. Turn to face the sun and the air glows; turn your back on
it and, with forward scattering, it almost disappears.

{{code settings}}

Drag Reach up and the beam extends further into the room. Drag it down and the
beam stops short, spending its samples on the part of the air closest to the
doorway.

> **Warning.** Turn Density to 0 and the pass is skipped. Remove `castsShadow`
> from the sun instead and there is nothing left to march against: the shafts
> disappear because the map they read has nothing in it, which is the honest
> failure this effect is supposed to have.

## Step 4: Confirm it ran

{{code ran}}
