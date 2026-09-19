# Occlusion

`AudioScene` must not learn what a wall is; that belongs to the physics.
Instead it takes a callback, `occlusion`, and asks it how much of a sound
gets through between the source and the listener.

## Step 1: A wall as a question, not a shape

This page's wall is one line: crossing x = 2 halves what gets through.

{{code wall}}

## Step 2: A scene that asks it

{{code scene}}

## Step 3: Listen from both sides

{{code listen}}

With the listener on the near side of the wall, the sound behind it plays
at half its usual gain and reports itself half muffled. Move the listener
past the wall to the sound's own side, and it plays clearly again.
