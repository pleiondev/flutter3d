# Additive layers

An ordinary layer replaces the base's pose for the joints it covers. An
additive layer does something else: it measures how far its own clip has
moved from its own rest frame, and lays that difference on top of the base
instead. This page turns a head steadily to one side and adds a quick twitch
without undoing the turn.

## Step 1: A clip that names its own rest frame

The turn clip holds one rotation the whole time; the head never stops facing
that way on its own. The twitch clip is different: it names a
`referenceTime`, the moment its own difference is measured from. At that
moment it asks for nothing, which is what makes it safe to add rather than
replace.

{{code clips}}

## Step 2: Play it additively

`playLayer` takes a `blend`. `AnimationBlend.additive` is what turns "this
clip's pose" into "this clip's distance from its own rest frame, added to
whatever the base is already doing".

{{code additive}}

## Step 3: Advance it

{{code live}}

## What to look at

The head keeps its steady turn the entire time; the twitch never resets it,
because nothing here replaces the turn's own value. What the twitch adds is
only the difference between where its clip is right now and where it sits at
its own reference time — a delta, not a destination.
