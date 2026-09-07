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

## What is not here yet

No economy, no production, no fight, no fog of war. Those are later phases; a
package that grew them before it could carry a crowd across a hill would have
been guessing about the uncertain part.
