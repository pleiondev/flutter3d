# Voice limiting

A device only mixes so many sounds well before a scene stops having a
foreground. `AudioScene(maxVoices:)` caps how many voices exist at once, and
priority decides which ones survive when there are more candidates than
slots.

## Step 1: A scene with three voices

`SoundDef.priority` breaks the tie a device's own limit cannot: a shout
outranks a footstep even when the footstep is closer.

{{code scene}}

## Step 2: Ask for five

Four footsteps and one shout, in a scene that only has room for three.

{{code crowd}}

## Step 3: See who kept a voice

After `update`, only the highest-priority, loudest sounds still hold a
voice. A one-shot that lost the vote is not merely quiet, it is removed
outright: there is nothing left for it to finish.

{{code read}}

The shout, ranked far above every footstep, is one of the three that made
it through.

## Step 4: Crowd the scene

The blue block is the listener; the coloured balls are the sounds asking to be
heard, footsteps at growing distances round it and one shout across the room.
A lit ball got a voice and a dark one lost the vote. The shout wins over every
footstep because it is the higher priority, and among the footsteps the nearer
ones win, however many ask. Raise or lower **Voices allowed** and watch the
lit ones change; the purple bar is how many voices are in use.

{{code live}}
