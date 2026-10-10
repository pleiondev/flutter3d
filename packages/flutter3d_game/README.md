# flutter3d_game

What a game on flutter3d adds to an application: the devices it is played with,
the run being played, the settings and saves a player keeps, and a drawn view
of what a level's simulation moves. The widgets over all of it (touch
controls, the settings panel, the credits, the HUD) are
[`flutter3d_game_ui`](https://pub.dev/packages/flutter3d_game_ui)'s.

It depends on [`flutter3d_app`](https://pub.dev/packages/flutter3d_app) for the
surface, storage and level loading every application shares, and on
[`flutter3d_sim`](https://pub.dev/packages/flutter3d_sim) for the fixed step, levels, actors and saves.
It re-exports `flutter3d`, and from `flutter3d_app` the view a game is
drawn in; everything else in `flutter3d_app` and `flutter3d_sim` stays
theirs, and a file that needs more imports them. The simulation is plain Dart
and lives in `flutter3d_sim`.

## What is in it

| | |
|---|---|
| `ActionMap` / `DesktopInput` / `PadInput` | Input that has forgotten which device it came from: a key, a touch stick (`flutter3d_game_ui`'s `TouchControls`) and a gamepad button arrive as the same `GameAction`, through one action map a player rebinds and the settings file keeps. |
| `RunSession` | Loading a level, restarting it, moving to the next, saving and resuming, and reporting how the run ended. |
| `GameSettings` / `GameSettingsController` | The player's settings as a value — a volume per `AudioBus`, typed `SettingKey`s, the action map — and the controller that saves each change. The panel that changes them is `flutter3d_game_ui`'s `SettingsOverlay`. |
| `SaveFile` / `SettingsFile` / `DemoFile` | The three documents a game keeps, through `flutter3d_app`'s `Storage`. |
| `LevelWalk` | The walk a level starts with, before it is any genre: a body that collides, jumps and runs, turns where it is dragged, and carries a camera at eye height. |
| `ActorVisuals` / `FixtureVisuals` | An actor bound to the node that represents it, and a fixture to the light it drives. The game decides what a torch looks like and hands it in. |

## Input

One `ActionMap` holds every binding a game has: the buttons, the composites
(WASD as one move), the sticks and the mouse's motion, each with its dead
zone, sensitivity and invert. A game makes it once and hands the same object
to the keyboard, the pad and the settings screen, so a rebind takes effect on
the next key press:

```dart
final settings = await SettingsFile(
  appName: 'my_game',
  defaultActions: DesktopInput.defaultActionMap,
).read();
final actions = PadInput.addDefaultsTo(
  settings.actionsOr(DesktopInput.defaultActionMap),
);
final keyboard = DesktopInput(state: input, actions: actions);
final pad = PadInput(state: input, actions: actions)..applySettings(settings);
```

What a gamepad's controls do is bindings too. The left stick walks through a
`DualAxisBinding` on `pad:stick.left`, the right one looks; a racing game
starts from `PadInput.addDrivingDefaultsTo`, which binds the stick's two
directions (`InputSource.padHalfAxis`) to its steering as buttons with a
magnitude. A numbered slot — a weapon, a hotbar's block — is an action of
`SlotActions`, bound to the number row by default and to the d-pad by
`PadInput.addSlotDefaultsTo`.

## Settings

`GameSettings` is a value: `withVolume(AudioBus.music, 0.4)`,
`withValue(GameSettingKeys.mouseLook, 1.5)`, `copyWith(...)`. A game's own
setting is a `SettingKey` under its own namespace,
`SettingKey<bool>('mygame.subtitles', fallback: true)`. The file is written
in the format envelope (`f3d.settings`), and a file from before it is read and
its names moved to their namespaced ids.

`GameSettingsController` holds the current value, saves every change and
hands it to the game's `apply`. The panel, `flutter3d_game_ui`'s, is a list
of `SettingsSection`s:

```dart
import 'package:flutter3d_game_ui/settings.dart';

SettingsOverlay(
  settings: controller,
  opening: keyboard.releaseMouse,
  sections: SettingsSection.standard(
    defaultActions: DesktopInput.defaultActionMap,
    padConnected: pad.isConnected,
  ),
)
```

## What is deliberately not in it

Widgets. Every one of them is `flutter3d_game_ui`'s, so a test or a
replaying server that reads the settings and the run resolves none of them.

Anything a particular game says. The list of rebindable actions belongs to
the caller, and the settings have never known what a coin or a monster is.

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
