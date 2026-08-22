# flutter3d_physics

Collision shapes, a broadphase grid, ray and overlap queries, rigid bodies and a
character controller.

**No Flutter and no renderer in it.** That is the boundary this package exists
to keep: it runs under `dart test`, and the day it needs a widget is the day
something has been put in the wrong package.

```dart
final world = CollisionWorld();
world.add(Collider(shape: CollisionBox(Vector3(2, 1, 2))));

final body = CharacterController(world: world, position: Vector3(0, 2, 0));
body.step(dt, wishDirection: forward, sprint: false);
```

## What the character controller is for

Walking, which is harder than falling. Slopes it can climb and slopes it slides
off, steps it can walk up without a jump, ramps whose surface it follows, a
coyote window after walking off an edge and a buffered jump pressed just before
landing. Every one of those is a decision with a test beside it saying which way
it went and why.

## Tolerances

`Nearly` names the four magnitudes this package compares against, because the
number was never the interesting part: a distance nobody can perceive, the slack
on two numbers computed different ways, and a denominator guard on a squared
quantity are different questions that used to look identical.
