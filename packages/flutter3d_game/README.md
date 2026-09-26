# flutter3d_game

What a game on flutter3d adds to an application: the devices it is played with,
the run being played, the screens a player uses outside the game itself, and a
drawn view of what a level's simulation moves.

It depends on [`flutter3d_app`](https://pub.dev/packages/flutter3d_app) for the
surface, storage and level loading every application shares, and on
[`flutter3d_sim`](https://pub.dev/packages/flutter3d_sim) for the fixed step, levels, actors and saves.
It re-exports neither. The simulation is plain Dart and lives in `flutter3d_sim`.

## What is in it

| | |
|---|---|
| `DesktopInput` / `TouchControls` / `PadInput` / `Bindings` | Input that has forgotten which device it came from: a key, a touch stick and a gamepad button arrive as the same `GameAction`. |
| `RunSession` | Loading a level, restarting it, moving to the next, saving and resuming, and reporting how the run ended. |
| `SettingsOverlay` | Volumes, gamepad and accessibility sliders, a rebinding list that takes a key or a pad button, and where a licence's attribution goes. |
| `SaveFile` / `SettingsFile` / `DemoFile` | The three documents a game keeps, through `flutter3d_app`'s `Storage`. |
| `LevelWalk` | The walk a level starts with, before it is any genre: a body that collides, jumps and runs, turns where it is dragged, and carries a camera at eye height. |
| `ActorVisuals` / `FixtureVisuals` | An actor bound to the node that represents it, and a fixture to the light it drives. The game decides what a torch looks like and hands it in. |

## What is deliberately not in it

The title card and the loss screen. Those belong to a particular game, and
sharing them would give three games the same title screen.

Anything a particular game says. The credits are a widget the caller hands in,
the list of rebindable actions belongs to the caller, and the panel has never
known what a coin or a monster is.

A state-management choice. `RunSession` is an ordinary class. Two of the three
games wrap it in a cubit, and the package does not depend on that.

The racing game's season. Racing moves from one circuit to the next and keeps
how far somebody got, which looks like a `RunSession` but is not one: nobody
resumes a race half a lap in, so `snapshotOf` and `restoreInto` would be two
required overrides returning nothing.

## One assembly per game

Every game has exactly one function that turns a level document into a run
(`stage` in each application), and nothing else spawns a level. The platformer
once had six copies of that assembly and they had drifted apart. The dungeon
had two, and one of them proved the crypt finishable with a loadout the game
never gives anybody. `dart run tool/structure.dart` checks the rule.

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
