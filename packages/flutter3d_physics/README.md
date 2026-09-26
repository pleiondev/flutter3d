# flutter3d_physics

Collision shapes, a broadphase grid, ray and overlap queries, rigid bodies and a
character controller.

The package contains no Flutter and no renderer. It runs under `dart test`, and
keeping it that way is the reason it is a separate package: if it ever needs a
widget, something has been put in the wrong package.

```dart
final world = CollisionWorld();
world.add(Collider(shape: CollisionBox(Vector3(2, 1, 2))));

final body = CharacterController(world: world, position: Vector3(0, 2, 0));
body.step(dt, wishDirection: forward, sprint: false);
```

## What the character controller is for

Walking, which is harder than falling. The controller handles slopes it can
climb and slopes it slides off, steps it can walk up without a jump, ramps whose
surface it follows, a coyote window after walking off an edge, and a buffered
jump pressed just before landing. Each of those is a decision, and each has a
test beside it saying which way it went and why.

## Ground, and the joins in it

`CollisionHeightfield` is a field of samples a body can walk on. It is the fifth
shape, and the first that is not one convex solid. A query names the box it
cares about, the shape hands back the convex pieces near it, and the plane walk
that every other query already used runs once per piece.

The joins are where this can go wrong. Where two triangles meet, each piece
ends in a vertical face that the other continues through, and a sweep that
reports one of those faces stops the body dead against a wall nobody drew. The
shape names those faces and the world refuses to contact them.
`heightfield_test.dart` holds the two measurements that catch it going wrong,
and `tool/ground_cost.dart` measures what the whole thing costs.

## Tolerances

`Nearly` names the four magnitudes this package compares against, because the
number itself was never what mattered. A distance nobody can perceive, the
slack between two numbers computed different ways, and a denominator guard on a
squared quantity are different questions, and they used to look identical.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an independent
implementation of a 3D engine for Flutter. It is not a fork or a binding of
another engine, and it is not affiliated with the Flutter team. It has four
switchable rendering backends: Impeller via Flutter GPU, WebGL2, WebGPU and a
software rasteriser. It loads glTF, OBJ and `.f3d`, and has six lighting models,
shadows, bloom, skinning, animation, BVH culling and picking, plus a
deterministic fixed-step game layer with collision, navigation, positional
audio, and gamepad and touch input. Four example games (shooter, platformer,
racing, strategy) are each built on a genre package:
[`flutter3d_game_shooter`](https://pub.dev/packages/flutter3d_game_shooter),
[`flutter3d_game_platformer`](https://pub.dev/packages/flutter3d_game_platformer),
[`flutter3d_game_racing`](https://pub.dev/packages/flutter3d_game_racing),
[`flutter3d_game_strategy`](https://pub.dev/packages/flutter3d_game_strategy).
A new game starts from the editor's scaffold, which writes one from a template:
<https://flutter3d.pleion.dev/first-project/>. Documentation:
<https://flutter3d.pleion.dev>.
