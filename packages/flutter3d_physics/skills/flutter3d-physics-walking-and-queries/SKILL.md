---
name: flutter3d-physics-walking-and-queries
description: Use when adding collision, raycasts, overlap queries or a walking body with flutter3d_physics — the world, the character controller's rules, heightfield ground and the tolerances.
---

# A world, some colliders, and a body that walks

```dart
final world = CollisionWorld(cellSize: 4);
world.addBox(Vector3.zero(), Vector3(20, 1, 20));
world.add(Collider(shape: CollisionSphere(0.5), position: …, layer: 1 << 3));

final body = CharacterController(world: world, position: Vector3(0, 2, 0));

// once a step, in this order
body.step(dt, wishDirection: forward, sprint: false);
world.update();
```

No Flutter and no renderer here; it runs under `dart test`.

`CharacterController` registers its own collider, so monsters see the player as
an obstacle and triggers see them walk in. A body that only reads the world is a
body nothing else can react to.

`world.update()` reindexes what moved: call it after the bodies have stepped and
before the next round of queries, or a sweep answers about last step's
positions. `removeLater` is the safe removal from inside a callback.

## Queries

`sweep`, `raycast`, `overlap` and `depenetrate`, each taking the layers it cares
about and visiting candidates from the grid. `cellSize` is the trade, and 4
metres suits a scene built at human scale.

Do not build swept collision on top of `raycast`. A ray is infinitely thin and a
body is not; a corner a ray slips through is a corner a body catches on, which
only appears at speed and looks like teleporting.

## What the character controller decides

Slopes it can climb and slopes it slides off, steps it walks up without a jump,
ramps it follows, a coyote window after walking off an edge, a jump buffered
just before landing. Each is a decision with a test beside it saying which way
it went — change `MovementTuning`, not the order of the step.

That order is load-bearing: carry with the ground, resolve overlap, accelerate,
gravity, jump, move horizontally, then settle vertically. Moving before
depenetrating puts a body inside geometry it was already touching.

## Ground made of samples

`CollisionHeightfield` is the fifth shape and the first that is not one convex
solid. A query names the box it cares about, the field hands back the convex
pieces near it, and the same plane walk every other query uses runs once per
piece.

The joins are the part worth knowing: where two triangles meet, each piece ends
in a vertical face the other continues through, and a sweep reporting one stops
the body dead against a wall nobody drew. The shape names those faces and the
world refuses to contact them. `heightfield_test.dart` holds the two
measurements that catch it going wrong.

## Compare against a named tolerance

`Nearly` names the four magnitudes this package compares against. A distance
nobody can perceive, the slack between two numbers computed different ways, and
a denominator guard on a squared quantity are different questions that look
identical when they are all `1e-6`.

## Snapshots

`snapshot.dart` reads and writes the world's state as data, so a save, a replay
and a digest see the same bits. Anything mutable a step depends on belongs in
there, or a restored run diverges from the recorded one.
