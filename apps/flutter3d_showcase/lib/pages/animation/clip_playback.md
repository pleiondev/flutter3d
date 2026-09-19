# Clips and crossfades

`AnimationPlayer` plays one clip on a set of nodes. This page gives it two:
a slow spin and a short nod, and asks it to move from the first to the second
without the cube snapping between them.

## Step 1: Two clips, one target

Each clip is a list of tracks; each track names a node index, a path
(rotation, here) and its keyframes. Both clips only ever touch node 0, the
cube, so they compete for the same joint rather than moving different parts.

{{code clips}}

## Step 2: Play one, then fade to the other

`AnimationPlayer` needs the clips and the list of targets they can address,
index-aligned. `play(0)` starts the `spin`. `crossFadeTo(1, duration: 0.4)`
does not cut to the `nod`: it keeps the `spin` playing while the `nod`'s own
pose is mixed in over four tenths of a second, so the cube's rotation moves
smoothly from one performance to the other instead of jumping.

{{code player}}

## Step 3: Advance it every frame

A player does nothing on its own. `update` moves its playhead by the time
that passed and writes the resulting pose onto the cube.

{{code live}}

## Speed and wrap

The Speed slider multiplies how fast the playhead moves: low and the `spin`
crawls, high and it races. Wrap decides what happens when a clip reaches its
end: Loop starts over, Once holds the last pose, and Ping-pong plays
backwards to the start and forwards again. Change Wrap while the cube is
spinning and watch what happens at the end of a turn.
