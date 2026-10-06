# flutter3d_editor_play

Play from a level editor. The game a level belongs to is run with
`flutter run --machine`, reloaded, restarted and stopped from the editor, and
a level saved while it runs is sent to it and taken without the game starting
over.

It is what the Play button of `apps/flutter3d_editor` runs, and what the
`play` tools of [`flutter3d_editor_mcp`](../flutter3d_editor_mcp) run, so an
agent's Play and a person's are the same code.

```dart
final root = projectRootOnDisk('game/assets/levels/first.json');
final run = FlutterRun(projectRoot: root!, device: 'macos');
await run.start();
run.state.changes.listen((PlayState state) => print(state));

// Later, after the code changed:
print(await run.hotSwap()); // "Reloaded 3 of 812 libraries"

// After a save:
if (run.state.value case PlayRunning(:final vmService)) {
  print(describeLevelApplied(await pushLevel(vmService, savedDocument)));
}
```

| | |
|---|---|
| `FlutterRun` | One `flutter run --machine`: its state, its console, the events the game posts, reload, restart, stop |
| `projectRootFor`, `projectRootOnDisk` | The project a level file belongs to: the nearest `pubspec.yaml` above it |
| `flutterDevices`, `parseFlutterDevices` | What `-d` can be given, from `flutter devices --machine` |
| `pushLevel` | A saved level, sent to the running game's `ext.flutter3d.level.apply` — or, given the `base` it was saved over, as a patch to `ext.flutter3d.level.patch`, whole only when the game says the patch is stale |
| `Watched` | A value and a stream of its changes, where Flutter's `ValueNotifier` cannot go |
| `AttachedRun` | A game somebody else started, by its VM service address: console, events, hot reload and restart, detach |
| `PostedEvent`, `eventsSince` | What the game posted with `flutter3d_game`'s `postGameEvent` — numbered, capped like the console — and the read by cursor that `play_events` answers with |
| `PlayedGame` | What `FlutterRun` and `AttachedRun` both are, for one panel over either |
| `connectVmService` | A VM service connection over a socket a browser has too |

`package:flutter3d_editor_play/testing.dart` has `FakeFlutterTool`, a
`flutter run --machine` a test controls, and `fakeFlutterRun` over it;
`FakeGame`, a VM service a test controls (`posts` is the game posting an
event), and `fakeAttachedRun` over it; `fakeFlutterRun(game:)` finds it at
the address the tool reports.

## In a browser

A web build has no process to start, so it imports
`package:flutter3d_editor_play/attach.dart`, which has no `dart:io` under it,
and attaches to a game that is already running:

```dart
final game = AttachedRun('http://127.0.0.1:8181/abc=/'); // what the game printed
await game.start();
print(await game.hotSwap()); // "Swapped in the new code"
print(describeLevelApplied(await pushLevel(game.vmService, savedDocument)));
await game.stop(); // lets go; the game keeps running
```

The hot reload is not the VM's: a Flutter game cannot compile its own new
code. The `flutter run` or `flutter attach` connected to it registers
`reloadSources` and `hotRestart` on its VM service, and `AttachedRun` calls
those, as DevTools does. With no tool connected it says so and what to run.
Checked against a real macOS game from the Dart VM and from Chrome, on a
page served from `localhost`.

## Why a package of its own

Play starts a process and talks to it. `flutter3d_editor_core` is written
never to do either, so a validator or a web build can open a level with it,
and the editor's MCP server could not reach code that lived inside the editor
application. Here both depend on it, and neither on the other. It is plain
Dart with `dart:io`: it runs under `dart run` and in a desktop app, and only
`attach.dart` of it in a browser, where there is no process to start.

The game side of it, the extension a level is sent to, is `LiveLevel` in
`flutter3d_game`.
