# flutter3d_game

What a game on flutter3d adds to an application: the devices it is played with,
the run being played, the screens a player uses that are not the game, and what
a level's simulation moves, drawn.

It stands on [`flutter3d_app`](../flutter3d_app) — the surface, storage and
level loading every application shares — and on
[`flutter3d_sim`](../flutter3d_sim), the fixed step, levels, actors and saves,
and re-exports neither. The simulation is plain Dart and lives there.

## What is in it

| | |
|---|---|
| `DesktopInput` / `TouchControls` / `PadInput` / `Bindings` | Input that has forgotten which device it came from: a key, a touch stick and a gamepad button arrive as the same `GameAction`. |
| `RunSession` | Loading a level, restarting it, moving to the next, saving and resuming, and reporting how the run ended. |
| `SettingsOverlay` | Volumes, gamepad and accessibility sliders, a rebinding list that takes a key or a pad button, and where a licence's attribution goes. |
| `SaveFile` / `SettingsFile` / `DemoFile` | The three documents a game keeps, through `flutter3d_app`'s `Storage`. |
| `ActorVisuals` / `FixtureVisuals` | An actor bound to the node that represents it, and a fixture to the light it drives. What a torch looks like is decided by the game and handed in. |

## What is deliberately not in it

**The title card and the loss screen.** Those are the face of a particular game.
Three identical title screens would be a loss, not a saving.

**Anything a particular game says.** The credits are a widget the caller hands
in, the list of rebindable actions is the caller's, and the panel has never
known what a coin or a monster is.

**A state-management choice.** `RunSession` is an ordinary class. Two of the
three games wrap it in a cubit and the package neither knows nor cares.

**The racing game's season.** Racing moves from one circuit to the next and
keeps where somebody got to, which looks like a `RunSession` and is not one:
nobody resumes a race half a lap in, so `snapshotOf` and `restoreInto` would be
two required overrides returning nothing.

## One assembly per game

Every game has exactly one function that turns a level document into a run —
`stage` in each application — and nothing else spawns a level. The platformer
had six copies of that assembly and they had drifted; the dungeon had two, and
one of them proved the crypt finishable with a loadout the game never gives
anybody. `dart run tool/structure.dart` checks it.

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
[`flutter3d_game_racing`](../flutter3d_game_racing). A new game starts from the
editor's scaffold, which writes one from a template: <https://flutter3d.pleion.dev/first-project/>.
Documentation: <https://flutter3d.pleion.dev>.
