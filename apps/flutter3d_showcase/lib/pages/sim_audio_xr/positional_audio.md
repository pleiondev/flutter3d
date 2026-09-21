# Positional audio

`AudioScene` decides what is heard and how loudly, from the position of every
sound and the listener's position and facing. The geometry is computed in
Dart rather than left to the backend, because a listener that turns every
frame needs the pan to follow it immediately.

## Step 1: A scene with one sound

`SilentBackend` makes no sound and records what it is asked for, which is
what lets a page like this one run with nothing behind it.

{{code scene}}

## Step 2: Play it and measure it

`play` starts an emitter at a position. `update` recomputes every emitter's
gain and pan against a listener, once a frame.

{{code play}}

With the source four metres to the side, the listener hears it panned hard
to that side.

## Step 3: Move the listener

{{code move}}

Turning to face the source directly centres the pan, and stepping closer
raises the gain: `InverseRolloff`, the default attenuation curve, gets
louder the nearer the reference distance a sound is heard from.

## Step 4: Walk round the bell

The same two calls, made every frame. The blue block is the listener and its
white nose is the way it faces; it walks round the bell, or wherever the
sliders put it. The bell swells with how loud it is heard, the yellow bar is
that gain, and the knob on the rail is the pan, from the left ear to the right.
Turn the listener away and the pan swings, though the distance has not changed.

{{code live}}

{{code hear}}
