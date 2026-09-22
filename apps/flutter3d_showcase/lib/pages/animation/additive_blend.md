# Additive layers

An ordinary layer replaces the base's pose for the joints it covers. An
additive layer does something else: it measures how far its own clip has
moved from its own rest frame, and lays that difference on top of the base
instead. This page turns three heads at the same steady rate, then nods the
right two in the same way every couple of seconds. The left head only turns,
so there is something to compare against.

## Step 1: A clip that names its own rest frame

The turn clip is a full revolution, one keyframe per quarter turn. The nod is
different: it names a `referenceTime`, the moment its own difference is
measured from. At that moment it asks for nothing, which is what makes it
safe to add rather than replace.

{{code clips}}

## Step 2: Play it additively

`playLayer` takes a `blend`. `AnimationBlend.additive` turns "this clip's
pose" into "this clip's distance from its own rest frame, added to whatever
the base is already doing". The middle head gets this. The right head gets
the same clip with `AnimationBlend.override`, which is what a layer did
before there was a choice.

{{code additive}}

## Step 3: Advance it

The nod is played again every couple of seconds. The override layer is taken
off once it has finished: a layer stays at full weight on its last pose until
somebody removes it, and that last pose is the head facing dead ahead.

{{code live}}

## What to look at

All three heads turn together. When the nod arrives, the middle head nods and
keeps turning, because nothing replaces the turn's own value: the nod adds
only the difference between where its clip is right now and where it sits at
its own reference time. The right head does the nod too, but for as long as
it lasts the head stops turning and faces front, then picks the turn up
again. Drag **Turn speed** to zero and the difference shows most plainly: the
middle head nods from wherever it stopped, the right head still snaps
forward first.

## Step 4: What this page checks

The middle head has to be exactly the turn with the nod on top, and the
right head has to look different from it while the nod plays.

{{code check}}
