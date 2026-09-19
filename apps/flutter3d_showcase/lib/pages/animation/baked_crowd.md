# A crowd from a baked clip

A skinned draw hands the vertex stage one uniform array of joint matrices,
and a uniform is the same for every copy of an instanced draw. Give a
thousand villagers a skeleton apiece and they all stand in the pose the last
one set. `BakedPoses` sidesteps this by sampling every clip once, ahead of
time, into a table: from then on an instance only needs which clip and how
far into it, the two numbers instancing already carries per copy.

## Step 1: Build the rig once

The table is sampled from an ordinary rig, the same shoulder-and-arm chain a
single skinned character would use. Nothing about it knows it is about to
become a table.

{{code rig}}

## Step 2: Bake every clip into one table

Two clips, a slow wave and a fast one, go into one call. The table comes back
as a flat list of matrices: `clips` rows deep, `frames` rows a clip, four
floats a column, one joint's worth of columns per matrix.

{{code bake}}

> **Note.** The clip is baked, not the pose. A crowd built this way plays
> clips: no per-instance inverse kinematics, nothing that computes a pose
> from the world at run time, since that pose would need to reach a texture
> that frame and the table is built once and never again.

## Step 3: Read a row per instance, every frame

This is the part a vertex shader would do by sampling the texture at a row
worked out from the instance's clip and time. Nothing here touches the
skeleton: the table already has the answer, so each instance is only ever
two lookups and a blend between them.

A joint matrix is a delta from rest, not a place in the world: the shoulder's
row is the identity until it turns. Composing it with the arm's own rest
offset is what turns "how far the shoulder has swung" back into "where the
arm hangs now".

{{code read}}

Six figures share the one table, half on the slow clip and half on the fast
one, each started at a different point in its clip so they do not wave in
step.
