# flutter3d_game_platformer

A jump with a memory, a purse, a crate to push, and the floors all of it happens
on.

## Why it exists at all

This package was written to test the engine. SPEC stage 5 asks for "a game
that is not a shooter, without a single edit in `lib/src/`", and what mattered
was what the attempt found. Imagining this game had already dug three
hardcoded object types out of the engine, and sketching it for real found five
more, all in input. They were fixed instead of worked around, which is why the
engine below has no idea what a coin is.

It took these from the engine unchanged: the fixed step, the character
controller, the level format and its validator, the entity registry,
mechanisms, movers, riders, exits, health, the ECS and the snapshot. What it
had to bring itself is the list below.

## What is in it

| | |
|---|---|
| `PlatformerSimulation` | The step order: input, jump, movement, riders, hazards, collectibles, exits. |
| `Runner`, `RunnerTuning` | The jump policy: coyote time, jump buffering, a second jump, a dash, a drop through a one-way floor. |
| `Surfaces` | What a floor is made of. Ice, moss and mud are a table on the brushes instead of three special cases. |
| `Purse`, `Collectible` | What is picked up and what the total is at the end. |
| `Crate`, `Spring`, `Hazard`, `Checkpoint`, `Patrol`, `Leaper` | The furniture and the things that walk about in it, each one an entity kind the level format spawns. |
| `FollowCamera` | A camera that leads, kicks, shakes and widens, and respects reduce-motion. |

## Nothing here draws

No import reaches the renderer, so every one of the thirteen test files runs in
a test with no device. A screenshot cannot show the forgiveness a jump needs,
and that is the part players feel first.

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
