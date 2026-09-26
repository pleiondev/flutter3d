# flutter3d_game_shooter

What a monster is, what a shotgun does, what a medkit gives, and what order a
shooter's step runs in.

## The line

`flutter3d_game` knows what a body, a brain, a mechanism and a step are. It does
not know what any of them are for. The whole repository keeps one rule about
this: machinery stays, vocabulary moves.

`Mechanism`, `Actor`, `Takeable` and the level format are machinery, and they
live below. `Inventory`, `Gift`, `Arsenal`, `Monsters` and `GameSimulation`
answer that machinery with content, and content belongs to a genre. A platformer
gets none of it. That is the reason this package exists, and
`no_genre_test.dart` checks it one layer down instead of leaving it to
everyone's memory.

## What is in it

| | |
|---|---|
| `GameSimulation` | The step order of a shooter: aim, fire, projectiles, blasts, actors, pickups, mechanisms. |
| `Arsenal`, `WeaponDef`, `WeaponBehaviour` | Hitscan, projectile and blast, as data rather than as three classes. |
| `Bestiary`, `MonsterDef`, `ChaseBrain` | What a monster is: what it does when it sees you, when it hears you, and when it is hurt. |
| `Inventory`, `Gift`, `Pickup` | What is carried, what is given, and what refuses to be picked up because you are already full. |
| `Player` | An eye, a body and what it is holding. |

## Nothing here draws

No import in the simulation reaches the renderer or names Flutter, and
`tool/structure.dart` holds that line. `WeaponView` draws and the readouts are
widgets, which is why both are in `bridge.dart` and not in the barrel. A package
that can be tested without a device gets its bugs found in a second rather than
in a screenshot.

## What is deliberately still missing

Monsters do not fight each other, and there are no hit zones, secrets, score or
crouch. Each of those is a second consumer's worth of design and none of them
has one yet. They are named here so that the gap reads as a decision.

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
