---
name: flutter3d-game-strategy-crowds-and-orders
description: Use when building a strategy game on flutter3d — the crowd step, what an order costs, buildings that re-bake the grid, the fight, the economy and fog, and taped matches.
---

# A crowd, an order, and a grid coarser than a shooter's

```dart
final sim = StrategySimulation(ground: heightfield, random: GameRandom(7));
final worker = sim.add(Unit(position: Vector3(0, 0, 0)));   // UnitType.worker

sim.orders.moveTo(sim.units, Vector3(60, 0, 60));   // queued, obeyed next step
sim.step(1 / 60);
```

Give orders through `sim.orders` (`moveTo`, `attackWith`, `addAll`). They are
queued and carried out at the top of the next step, so **an order lands on a
step number rather than somewhere inside one** — which is what lets a tape index
its entries by step and get the same match back. `Squad(units, formation: …)`
writes the same orders straight onto units when no tape is involved.

An order from outside ends whatever loop a unit was running: `moveTo` clears the
job, because a squad order given to a busy harvester is otherwise overwritten by
the job before anybody moves, and that reads as disobedience.

`random` is required even though little rolls it yet: the other three genres
each shipped a game that took a default generator and diverged at the first roll
somebody later added.

## The step, in order

```
orders.obey → work → walk → fight → separate → sit → bury → produce → look
```

Jobs before the walk, so a harvester decides where it is going before anything
moves it — the difference between a stream of workers and a stutter of them.
The **fight goes between the walk and the shove**: shots are taken from where a
unit just arrived rather than from where it stood last step, and before
separation, so a pair that walked into each other is measured at the range they
reached instead of the range the shove left. The dead are collected once, after
both, because `separate` and `fight` hold places in `units` while they run. Fog
is refreshed last, so what a side knows agrees with where its crowd is.

## An order is what costs, and the walking is not

The same walk is 0.52 ms on a two-metre grid and 8.4 ms on a half-metre one,
while 10,000 agents step in under a millisecond and 50,000 instances hold a
120 Hz display. That is why this package bakes at two metres: before making the
grid finer, measure the order rather than the walk. `Formation` arranges a squad
where it arrives instead of giving every member its own goal, which keeps twenty
orders from costing twenty fields.

## Buildings move the ground out from under people

A `Building` is a footprint rather than a collider. Placing one takes its cells
out of the `NavGrid`, re-bakes, **and moves whoever was standing under it** — a
unit left in a cell no field can reach stops walking for the rest of the match
and says nothing about it.

## Kinds, the economy and the fog

`UnitType` is a row of numbers — radius, speed, sight, health, damage, range,
reload — and the default is the worker. Its `damage` of nought is what makes the
fight skip it entirely rather than what makes it lose one, so an unarmed kind
costs nothing in the fight loop.

`ResourceNode` is what the map holds, `HarvestJob` the loop a worker runs when
nobody is pointing, a `Stockpile` and a delivered total belong to a side, and a
`Producer` turns a pile back into units. `sides` defaults to two and is not a
law: everything a side owns is a slot in a list.

`FogOfWar` keeps explored (once anybody has been near a cell, for ever) and
visible (only while somebody is near it now). **The policy that decides where to
send workers asks it**, so a side that has not found a seam has to send somebody
to look, and the picture draws the lattice the rules read. Do not give a `Bot`
knowledge the fog denies a player.

## Saving and replaying a match

Units live in an `EcsWorld` because `produce` makes them while the match runs: a
snapshot taken at minute three describes more units than the freshly staged map
it is restored into, and saving unit *n* as the *n*th entry of a list restores
the wrong worker. `units` is still the order the step walks, and that order is
what makes a run repeat.

`OrderTape` is a match as a seed, a starting `Snapshot` and an entry per step —
the same arithmetic as `InputTape` and deliberately a different type, sharing
only `DemoFormatException`. Fed to the same simulation from the same starting
state it produces the same match, to the bit single precision has.

## What is not here yet

Sight is a radius rather than a line through the terrain — a ridge hides nobody,
because a ray per cell per source is the one cost here that grows with the crowd
and the map at once.
