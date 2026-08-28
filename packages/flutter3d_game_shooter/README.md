# flutter3d_game_shooter

What a monster is, what a shotgun does, what a medkit gives, and what order a
shooter's step runs in.

## The line

`flutter3d_game` knows what a body, a brain, a mechanism and a step are. It does
not know what any of them are *for*. The rule the whole repository keeps is one
sentence: **machinery stays, vocabulary moves.**

`Mechanism`, `Actor`, `Takeable` and the level format are machinery, and they
live below. `Inventory`, `Gift`, `Arsenal`, `Monsters` and `GameSimulation`
answer that machinery with content, and content belongs to a genre. A platformer
gets none of it — which is the whole reason this package exists, and is checked
by `no_genre_test.dart` one layer down rather than left to everyone's memory.

## What is in it

| | |
|---|---|
| `GameSimulation` | The step order of a shooter: aim, fire, projectiles, blasts, actors, pickups, mechanisms. |
| `Arsenal`, `WeaponDef`, `WeaponBehaviour` | Hitscan, projectile and blast, as data rather than as three classes. |
| `Bestiary`, `MonsterDef`, `ChaseBrain` | What a monster is: what it does when it sees you, when it hears you, and when it is hurt. |
| `Inventory`, `Gift`, `Pickup` | What is carried, what is given, and what refuses to be picked up because you are already full. |
| `Player` | An eye, a body and what it is holding. |

## Nothing here draws

No import reaches the renderer, and a test holds that line. `WeaponView` does
draw, which is why it is in `bridge.dart` and not in the barrel — a package that
can be tested without a device is a package whose bugs are found in a second
rather than in a screenshot.

## What is deliberately still missing

Monsters do not fight each other, there are no hit zones, no secrets, no score
and no crouch. Each of those is a second consumer's worth of design and none of
them has one yet; they are named here so that the gap reads as a decision.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an **independent
implementation** of a 3D engine for Flutter — not a fork or a binding of
another engine, and not affiliated with the Flutter team. Three switchable
rendering backends: Impeller via Flutter GPU, WebGL2, and a software
rasteriser. glTF, OBJ and `.f3d` loading, six lighting models, shadows, bloom,
skinning, animation, BVH culling and picking; a deterministic fixed-step game
layer with collision, navigation, positional audio, and gamepad and touch
input. Three example games — shooter, platformer, racing — each built on its
genre package: [`flutter3d_game_shooter`](../flutter3d_game_shooter),
[`flutter3d_game_platformer`](../flutter3d_game_platformer),
[`flutter3d_game_racing`](../flutter3d_game_racing). A new game starts from
[`apps/flutter3d_template_app`](../../apps/flutter3d_template_app).
Documentation: <https://flutter3d.pleion.dev>.
