# A time-travel debugger

The pause, step and rewind page shows the transport: a run stopped from
outside, one step taken by hand, a release into the past. That is enough to
see a moment again. It is not enough to debug one, because a release cuts
the buffer, and the second time you drag back you have already thrown away
the future you wanted to compare against.

`RunTimeline.scrubTo` is the other half. It moves the live state to any step
the rewind buffer holds and keeps everything: the tape, the keyframes and the
present, which it writes down on the first scrub. `returnToPresent` puts the
present back exactly. `branchHere` is the one call that cuts, and you ask for
it by name. Next to them, `tracks` reads the run as one lane per component of
each entity, and `bisectTapes` takes two runs of one tape and finds the step
and the component where they stop being the same run.

Drag **Scrub to step** on this page. The runner, the door and the target
move to wherever the run was before that step, and the right end of the
slider is the present.

## Step 1: A simulation the debugger can read

The toy has three entities written one row each under `entities`: a runner
that follows the stick, a door that opens when the runner reaches it, and a
target that loses health by the dice whenever fire is pressed. `save` and
`restore` are what any game already has for its rewind buffer. The random
generator's state and the step count are in the snapshot too, so a replay
from a keyframe rolls the same dice.

`EntityLayout.rows('entities')` is how the debugger is told where the
entities are. A snapshot is whatever a game wrote, and the engine cannot tell
an entity from a field on its own. For a game built on `EcsWorld`,
`EntityLayout.ecs` reads its save instead. Either way an entity's component is
named the same, `target.hp` here.

The `defectAt` field is a planted bug for Step 5. It is off in every run but
one.

{{code toy}}

## Step 2: Record the way a game loop records

The toy is a part of an `EngineLoop`'s snapshots and a system in its step,
and the buffer is attached to the loop (`rewind.attach(loop)`): each step
records its input into the buffer, and the buffer keeps the loop's own
capture as a keyframe when one is due. A game whose run is a part of its loop
— a genre's always is — gets the debugger without recording anything new,
and a rewind covers every part of the state, not only the toy. The page also keeps the state
before every step, which a game would not, so that the scrub can be checked
against it.

{{code record}}

## Step 3: Scrub without cutting

`scrubTo` only works while the timeline is paused. On a live run the loop
would step the scrubbed state as if it were the present, so the call is
refused with a `ScrubRefused` that says to pause first. A step the buffer no
longer holds is refused too, and the reason names the steps it does hold.

A scrub restores the nearest keyframe at or before the step and plays the
recorded input forward with the live devices muted, so a key you hold while
dragging does not leak into the replay. Dragging to the right from a scrubbed
step plays on from there rather than from the keyframe, so a drag costs about
the distance dragged.

{{code scrub}}

The page's check goes back and forth through the buffer, to steps 200, 240,
120, 121, 299, 0 and 200 again. Each scrub has to land on the digest of the
state recorded before that step, and `returnToPresent` has to give back the
present's digest with the tape still 300 steps long.

{{code back-and-forth}}

## Step 4: Lanes, and a branch

`tracks` lives the buffer again from its oldest keyframe, reads each step
through the layout and puts the live state back where it was. A lane holds a
sample only at the steps its value changed, so the door's lane is a few
entries however long the run, and those steps are where an editor's timeline
draws its marks. `at` answers the value in force at any step.

{{code tracks}}

The check asks that the lanes span the whole buffer, that the door's lane
holds the opening and closing, that the target's health at step 150 is the
one recorded there, and that reading the lanes left the run at the present.

`branchHere` makes the scrubbed moment the present. The tape after it is
cut, the same way `releaseAt` cuts it, but the timeline stays paused: you
are looking at the moment you chose, and the first step of the new branch is
yours to take. `releaseAt` is still there for a kill camera or a rewind
mechanic that wants the run to carry on at once.

{{code branch}}

## Step 5: Bisect two runs to a step and a component

A desync report is two runs of one tape that end in different places.
`bisectTapes` takes each as a `ReplaySide`: the state it starts from, the
tape, and the simulation's step, restore and capture. Each side needs its own
instance of the simulation, which also stops the two runs from sharing
anything by accident.

{{code bisect}}

The search compares digests at each probe and reads the two full snapshots
once, at the step it names. A side keeps the states it has been asked for and
plays on from the nearest one, so six hundred steps cost about ten
comparisons and at most twice the tape in stepping. The answer is a
`TapesDiverge`: the number of steps after which the runs differ (the tape
entry is one less), whether that entry's input differed, and through the
layout which entity and component moved.

{{code named}}

Here both runs have the same input, so `inputsDiffer` is false, which points
at the code or the platform rather than at a different recording. If you
have two `DigestTrace`s from the runs, `bracketFromTraces` narrows the
search to one checkpoint interval before it starts.

> **Note.** Bisection is a library call for now. Opening two `.f3drun`
> files side by side in the editor, and the same as tools for an agent, are
> later work. A scrub reaches only as far as the rewind buffer holds, not
> through the whole length of a loaded `.f3drun` unless one is rebuilt from
> it (`rewindBufferFromDemo`).
