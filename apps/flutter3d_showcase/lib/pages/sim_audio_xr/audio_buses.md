# Mixer buses

A settings screen usually has a music slider and an effects slider, and both
sit under a master. `AudioBus` names the groups and `Mixer` holds what each
one is turned to, read every frame so moving a slider is heard immediately.

## Step 1: A mixer

{{code mixer}}

## Step 2: Set some volumes

`setVolume` takes a bus and a level from 0 to 1.

{{code set}}

## Step 3: Read the gain a sound actually plays at

`gainFor` multiplies a bus's own volume by the master, since master is not a
special case, only another bus everything is also on.

{{code read}}

`AudioBus.sfx` is never configured on this page, and `gainFor` still answers
1.0 for it: an unset bus is full rather than silent, so a game that forgets
to configure one is still heard.
