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
| `FlutterRun` | One `flutter run --machine`: its state, its console, reload, restart, stop |
| `projectRootFor`, `projectRootOnDisk` | The project a level file belongs to: the nearest `pubspec.yaml` above it |
| `flutterDevices`, `parseFlutterDevices` | What `-d` can be given, from `flutter devices --machine` |
| `pushLevel` | A saved level, sent to the running game's `ext.flutter3d.level.apply` |
| `Watched` | A value and a stream of its changes, where Flutter's `ValueNotifier` cannot go |

`package:flutter3d_editor_play/testing.dart` has `FakeFlutterTool`, a
`flutter run --machine` a test controls, and `fakeFlutterRun` over it.

## Why a package of its own

Play starts a process and talks to it. `flutter3d_editor_core` is written
never to do either, so a validator or a web build can open a level with it,
and the editor's MCP server could not reach code that lived inside the editor
application. Here both depend on it, and neither on the other. It is plain
Dart with `dart:io`: it runs under `dart run` and in a desktop app, and not in
a browser, where there is no process to start.

The game side of it, the extension a level is sent to, is `LiveLevel` in
`flutter3d_game`.
