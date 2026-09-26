# flutter3d_game_strategy

A fourth genre: the ground is made of samples, units move as a crowd instead of
one at a time, and orders go to a selection instead of to a body.

```dart
final sim = StrategySimulation(ground: heightfield);
for (var i = 0; i < 500; i++) {
  sim.add(Unit(position: Vector3(i % 25 * 1.5, 0.0, i ~/ 25 * 1.5)));
}

for (final unit in sim.units) {
  unit.order = UnitOrder.moveTo(Vector3(60.0, 0.0, 60.0));
}
sim.step(1.0 / 60.0);
```

## Why a strategy is the fourth genre

The three genres before it each move one body under a camera attached to it.
When they agree about what an engine owes a game, that agreement says less than
it seems to, because all three have the same shape. A strategy game has the
other shape: a camera over a map, orders given to a selection, a crowd in place
of a hero. It is also the first game to use three things the engine already had
and nothing had exercised yet: instanced meshes, the picking pass, and the flow
fields in the navigation.

## What is measured rather than assumed

| Question | Answer | Where it came from |
|---|---|---|
| What does a crowd cost to step? | 10 000 agents in under 1 ms | descend 256 µs, separation 717 µs, transforms 19 µs |
| What does a crowd cost to draw? | 50 000 hold a 120 Hz display | the ceiling above that is the CPU encoding the frame, ~0.07 µs an instance |
| What does an order cost? | 0.52 ms on a two-metre grid | 8.4 ms on a half-metre one, for the same walk |

The last row is why this package bakes a coarser grid than a shooter does. An
order pays for the field, and the units walking it cannot tell the difference.

## What is here

A `Unit` is a record of numbers, not a body. A `UnitOrder` points somewhere or
nowhere. Each step walks the crowd over a `Heightfield`: descend a shared field,
push overlapping neighbours apart, settle back onto the ground. The `NavGrid`
under all of that is baked at two metres and re-baked whenever a `Building`
takes cells out of it; a building is a footprint, not a collider. Placing a
building also moves any unit standing under it, because a unit left in a cell
that no field can reach stops walking for the rest of the match without any
error.

On top of the walking there is an economy. A `ResourceNode` is what the map
holds. A `HarvestJob` is the loop a worker runs when nobody is giving it
orders: out, dig, home, drop. A `Stockpile` belongs to a side, not to the map,
and a `Producer` turns a pile back into units.

`FogOfWar` keeps two states on a lattice of its own. A cell is explored once
anybody has been near it, and stays explored for good; it is visible only while
somebody is near it now. The fog is part of the rules as well as the picture.
The policy that decides where to send workers queries it, so a side that has
not found a seam cannot dig it and has to send somebody to look, and the
rendering draws the same lattice the rules read. `Bot` plays a side through the
same handles a player has, and `Match` runs two bots to an economic win, or to
a draw when neither side got further than the other.

Around the simulation, `MapCamera` watches a place instead of a body. It still
drives `CameraRig`, so it gets the rig's smoothing and first-frame cut without
a copy of its own. `Selection` finds units with a ray the application
unprojects. `Formation` arranges a squad at its destination instead of giving
every member its own goal, which is why twenty orders do not cost twenty
fields. `StrategyVisuals` is the one file in the package that draws.

## What is not here yet

There is no combat yet. A package that added it before it could carry a crowd
across a hill would have been guessing about the part that was actually
uncertain. Every unit is also the same kind: there are no types with different
reach or armour. Nothing here can be snapshotted, recorded or given a seeded
random source, so a run can be watched but not yet replayed or rolled back.

Sight is a radius, not a line through the terrain, so a ridge hides nobody.
Casting a ray per cell per source is the one cost in this genre that grows
with both the crowd and the map, and nothing has needed it yet. There are
exactly two sides, each with one stockpile and one delivered total. That is
enough for one policy playing itself, and not enough for a game.
