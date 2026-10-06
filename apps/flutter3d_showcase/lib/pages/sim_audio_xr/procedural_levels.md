# Levels from a seed

A level drawn by hand is one level. A generator makes a new one from a number,
and the same number makes the same level again, which is what lets a run be
replayed, a bug report name its level in one integer, and a server check a
score against the map it was set on.

`generateLevel` lays a grid of cells out by wave function collapse. Each cell
is a room with a doorway on some of its four sides, or nothing, and a doorway
has to meet a doorway in the next cell, so every way out of a room leads
somewhere. The largest group of rooms that join up is the level; the player
starts in its first room and the exit goes in the room farthest from it.

## Step 1: The rules

`LevelRules()` with nothing changed is already a playable level: four cells
across and three down, sixteen metres each, a ten-metre room in a cell that
gets one, and corridors three metres wide. This page changes only `density`,
how likely a cell is to be a room rather than empty ground.

{{code rules}}

## Step 2: A seed in, a level out

Everything chance decides comes from `GameRandom` seeded with the number
given. A grid that comes out with fewer than two joined rooms is no level, so
the generator tries the next seed, up to thirty-two of them, and the answer
names the seed that worked. That seed alone makes the level again.

Before a level is handed back it is checked against `ExitReachable`: the
navigation mesh is baked and a route asked for from the player's start to the
exit. A doorway a step too high would fail here, not in the player's hands.

{{code generate}}

## Step 3: Draw it

The rooms and corridors arrive as recipes, so a level saved to a file stays
short. `expandRecipes` turns them into the brushes a game loads. This page
draws each brush as a box, leaves the ceilings out so the camera can look in,
and puts a green ball on the player's start and a red one on the exit.

Drag **Seed** and the layout changes; drag it back and the same layout
returns. Lower **Room density** and the level shrinks to a few rooms in a
line; raise it and most cells are rooms with doorways on several sides.

{{code draw}}

## Step 4: What the page checks

Two calls with the same seed have to write the same document, byte for byte,
and the exit has to be reachable when the rule is asked again from outside the
generator.

{{code check}}

> **Note.** `generateLevelOffThread` does the same work in an isolate, so a
> game can make the next level while the player finishes this one. In the
> browser it runs in place. `erodeThermally` and `erodeHydraulically` belong
> to the same set of tools and shape a `Heightfield` rather than rooms; this
> page does not show them.
