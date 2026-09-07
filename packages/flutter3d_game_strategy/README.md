# flutter3d_game_strategy

A fourth genre: ground made of samples, units that move as a crowd rather than
one at a time, and orders given to a selection instead of to a body.

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

The three before it move one body under a camera bolted to it. Their agreeing
about what an engine owes a game says less than it looks, because they agree by
being the same shape. This one is the other shape — a camera over a map, orders
given to a selection, a crowd instead of a hero — and it is the first game to
use three things the engine had already built and nothing had ever exercised:
instanced meshes, the picking pass, and the flow fields in the navigation.

## What is measured rather than assumed

| Question | Answer | Where it came from |
|---|---|---|
| What does a crowd cost to step? | 10 000 agents in under 1 ms | descend 256 µs, separation 717 µs, transforms 19 µs |
| What does a crowd cost to draw? | 50 000 hold a 120 Hz display | the ceiling above that is the CPU encoding the frame, ~0.07 µs an instance |
| What does an order cost? | 0.52 ms on a two-metre grid | 8.4 ms on a half-metre one, for the same walk |

The last row is why the grid this package bakes is coarser than a shooter's:
the field is what an order pays for, and the units walking it cannot tell.

## What is here

A `Unit` is a record of numbers rather than a body, a `UnitOrder` points
somewhere or nowhere, and the step walks the crowd over a `Heightfield`:
descend a shared field, shove overlapping neighbours apart, sit back on the
ground. The `NavGrid` under all of that is baked at two metres, and re-baked
whenever a `Building` takes cells out of it — a building being a footprint, not
a collider. The same placement moves whoever was standing under it, because a
unit left in a cell no field can reach stops walking for the rest of the match
and says nothing about it.

On top of the walking there is an economy. A `ResourceNode` is what the map
holds, a `HarvestJob` is the loop a worker runs when nobody is pointing — out,
dig, home, drop — a `Stockpile` belongs to a side rather than to the map, and a
`Producer` turns a pile back into units. `FogOfWar` keeps two states on a
lattice of its own: explored once anybody has been near a cell, for ever, and
visible only while somebody is near it now. It is a rule and not a coat of
paint — the policy that decides where to send workers asks it, so a side that
has not found a seam cannot dig it and has to send somebody to look, and the
picture draws the same lattice the rules read. `Bot` plays a side through the
handles a player has, and `Match` runs two of them to an economic win, or to a
draw when neither side got further than the other.

Around the simulation: `MapCamera` watches a place instead of a body and still
turns `CameraRig`, so it inherits the smoothing and the first-frame cut rather
than growing its own; `Selection` finds units with a ray the application
unprojects; `Formation` arranges a squad where it arrives instead of giving
every member a goal of its own, which is what keeps twenty orders from costing
twenty fields; and `StrategyVisuals` is the one file in the package that draws.

## What is not here yet

No fight, and it is still the honest omission: a package that grew one before
it could carry a crowd across a hill would have been guessing about the part
that was actually uncertain. Everything a unit is, it is the same way — one
kind, no types with different reach or armour. Nothing here can be snapshotted,
taped or handed a seeded random, so a run can be watched but not yet replayed
or rolled back. Sight is a radius and not a line through the terrain: a ridge
hides nobody, because marching a ray per cell per source is the one cost in
this genre that grows with the crowd and the map at once, and nothing has asked
for it yet. And there are two sides, not a number of them — a stockpile and a
delivered total apiece, which is enough for one policy playing itself and not
enough for a game.
