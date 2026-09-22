# Pausing and stepping a running game

`RunTimeline` is the mechanism underneath an editor's transport controls:
pause, step one fixed frame at a time, preview a rewind before committing to
it, and release into the past so the run continues from there instead of
snapping back.

> **Note.** `flutter3d_game`'s real `RunTimeline` is not a dependency of
> this app, but every type in its body is: `RewindBuffer`, `InputState`,
> `InputTapePlayback` and `Snapshot` all come from `flutter3d_sim`. This
> page carries the class over whole rather than approximating it.

## Step 1: The timeline itself

{{code timeline}}

## Step 2: Play normally, then pause and step by hand

Twenty ordinary steps, recorded the way a game loop already records every
step for the rewind buffer.

{{code play}}

Paused, `stepOnce` advances the simulation by exactly one fixed step —
refused if the timeline is not paused, since a step taken on a running
timeline would be a second step nobody asked for.

{{code pause}}

## Step 3: Rewind and release

{{code rewind}}

Rewinding one second on a buffer stepping ten times a second lands on the
recorded state ten steps back — not on the manual step from the previous
section, because that step was never written to the tape. Releasing leaves
the timeline running, not paused: a release is asking to keep playing from
here.
