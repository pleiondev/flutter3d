# Replays and digests

A server that verifies a submitted run cannot compare two worlds by sending
them to each other; a snapshot is tens of kilobytes and a run is thousands of
steps. Instead, both sides hash their state every few steps into one number
each, and the run is verified when the numbers match. `DigestTrace` is that
checkpoint list, and it is what a `Demo` file carries alongside the level and
the tape of inputs a player made.

## Step 1: Two faithful recordings agree everywhere

`DigestTrace.observe` folds the state at a step into the trace, but only when
the step falls on a checkpoint. Two traces of the same run compare equal at
every one of them.

{{code agree}}

## Step 2: A drifted run parts company at a checkpoint

`divergenceFrom` compares this trace's digests against another list and
returns the first checkpoint that disagrees, or null when they never do. A
run whose state starts drifting at step 9 still matches the checkpoint before
that, at step 8, and disagrees from step 12 on.

{{code diverge}}

The divergence names the checkpoint, not the exact step the drift began: a
digest is only taken every so many steps, and finding the exact step means
re-running with a finer trace between the last checkpoint that agreed and the
first that did not.

## Step 3: Write it down and read it back

A `.f3drun` file carries the trace as hex digits. `toJson` and `fromJson`
round-trip it, and a trace read back this way agrees with the run it was
taken from exactly as well as the original does.

{{code wire}}

## Step 4: Slide the drift

Five checkpoints, one every four steps. The blue tower is the original run's
state there and the orange one the replay's; the lamp over each pair is green
while their digests agree and red once they do not. The replay's state drifts
by one from the step on the slider, and the first red lamp is the checkpoint
that covers it: the digest notices a difference far smaller than a tower's
height. Slide it to *never* and every lamp stays green.

{{code live}}
