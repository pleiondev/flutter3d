# Rewinding

A kill camera, a rewind mechanic and a replay of the last few seconds are the
same idea: keep a little of the recent past and play it forward again.
`RewindBuffer` does this cheaply by keeping one full snapshot a second and
only the raw inputs between them, rather than a snapshot every single step.

## Step 1: Set up the buffer and a cost trace

`stepsPerSecond` turns seconds into steps, `keyframeEvery` decides how often a
full snapshot is kept, and `history` is how far back a rewind may reach.
`StepTimeTrace` is unrelated to rewinding itself; it is measured alongside it
here because both ride on the same step loop.

{{code buffer}}

## Step 2: Record inputs and keyframes together

Each step, the loop records this step's input into the buffer's own recorder,
takes a snapshot when `keyframeDue` says to, and times the step itself.

{{code step}}

## Step 3: Rewind

`rewindBy` asks for the state some seconds ago. It returns the nearest
keyframe at or before that point, plus however many recorded inputs are left
to replay to reach the exact step asked for.

{{code rewind}}

Thirty steps in at ten steps a second is three seconds of play. Rewinding by
one second lands on step 20, which happens to sit exactly on a keyframe here,
so there is nothing left to replay.

## Step 4: Run it, and take it back

A runner runs along a track, ten steps a second. Each step records its input
and, every fifth, a keyframe; the blue ghost beside it is where the buffer says
the run stood a second ago, worked out afresh each frame from the nearest
keyframe and the steps to play forward from it. **Rewind one second** puts the
runner on the ghost and forgets the future that had been recorded, and the run
carries on from there. The purple bar is how much of the run the buffer holds.

{{code live}}

{{code back}}
