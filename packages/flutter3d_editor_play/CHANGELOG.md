## Unreleased

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
