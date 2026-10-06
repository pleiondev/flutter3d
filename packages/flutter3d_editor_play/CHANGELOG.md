## 0.9.0

- **The first publication.** The 0.8.0 the pubspec carried was a number
  inside the workspace and never reached pub.dev. The package goes out on the
  shelf's number, so `^0.9.0` on it resolves against every other
  `flutter3d_*` package.

- **The events a game posts, beside its console.** `PlayedGame.events`
  keeps what the game posted with `flutter3d_game`'s `postGameEvent` — a
  level loaded, the player died — each a `PostedEvent` with a sequence
  number, its kind without the `flutter3d.` prefix, a time and its data,
  capped at 2000 like the console. `AttachedRun` listens to the VM
  service's `Extension` stream on the socket it already has; `FlutterRun`
  opens one at the address `app.debugPort` reports, since the daemon carries
  prints and not posts, and drops it when the game exits. `eventsSince`
  reads the list by cursor, with the next cursor, how many the cap dropped
  unread, and a restart from the first for a cursor past the end.
- **`FakeGame.posts`** is the game posting an event, and `fakeFlutterRun`
  takes the `FakeGame` its run finds at the reported address.

- **`callGameExtension`** asks a running game for one of its extensions.
  It finds the isolate that registered it and returns the game's own
  answer or the reason it refused.

- **A save goes to the running game as a patch.** `pushLevel(base:)` sends
  the patch from `base` to the saved document when the game has
  `ext.flutter3d.level.patch` and the patch is shorter, and the whole
  document when the game answers that the patch is stale; the answer then
  carries `fellBack`, which `describeLevelApplied` puts at the end of its
  line. `levelPatchArguments` builds the parameters.
- **`AttachedRun` plays a game somebody else started**, by its VM service
  address: the console (with what the game printed before the attach, which
  DDS replays), hot reload and restart through the services the flutter tool
  registers on the game, and stop as a detach that leaves the game running.
  It is the only Play a browser has, and the editor's attach button on a
  desktop uses it too. `PlayedGame` is what it and `FlutterRun` both are, so
  one panel shows either; `PlayState` moves to `src/play_state.dart`, and
  `PlayStopped` takes a `reason` for an end with no exit code.
- **`package:flutter3d_editor_play/attach.dart`**: everything here that
  starts no process — `AttachedRun`, `pushLevel`, `connectVmService`,
  `PlayState`, `Watched` — with no `dart:io` anywhere under it, which a test
  walks the imports to check.
- **`connectVmService` instead of `vmServiceConnectUri`**, over
  `web_socket_channel`, so a level is sent from a browser as well;
  `vmServiceWebSocket` reads the `http://` address a game prints as well as
  the `ws://…/ws` one. `pushLevel` takes a `connect` for tests.
- **`FakeGame` and `fakeAttachedRun`** in `testing.dart`: a VM service with
  a flutter tool on it, or without one, that a test controls.
- **A stop on Windows ends the tool, not only its shell.** `flutter` there
  starts through `cmd.exe`, and `Process.kill` left the Dart process behind
  it building; a stop before the game has started now runs `taskkill /t`.
  `FlutterRun` takes the kill as a parameter, and `treeKillCommand` says
  which command a platform needs.

- **Play leaves the editor application.** `FlutterRun`, `projectRootFor`
  and `pushLevel` move here from `apps/flutter3d_editor/lib/src/play`, with
  `Watched` in place of Flutter's `ValueNotifier`, so the editor's MCP server
  runs the same Play. `FlutterRun.device` is settable between runs, and
  `hotSwap`/`hotRestart` return what the tool said.
- **`flutterDevices` lists what `flutter run -d` can be given**, from
  `flutter devices --machine`, reading past whatever the tool prints first
  and leaving out devices it marks unsupported.
- **`package:flutter3d_editor_play/testing.dart`**: `FakeFlutterTool` and
  `fakeFlutterRun`, a `flutter run --machine` a test controls.

Its `flutter3d_*` dependencies ask for `^0.9.0`.
