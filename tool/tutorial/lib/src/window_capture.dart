/// Shells out to `window_id.swift` and to macOS's own `screencapture` — the
/// two subprocesses `tut-00`'s plan describes: id from `tool/tutorial/
/// window_id.swift` through `CGWindowListCopyWindowInfo` by process name,
/// then `screencapture -l` with it. Nothing here has a real macOS window to
/// point at in this environment (no GUI, no running modeler) — see
/// `WindowCapture`'s own doc comment for exactly what that leaves
/// unverified.
library;

import 'dart:io';

/// A subprocess call, factored out so a test can hand [WindowCapture] a fake
/// one and inspect what it was asked to run instead of actually shelling
/// out to `swift` and `screencapture`.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Finds this app's on-screen window id and asks `screencapture` to save it.
///
/// **Untestable against the real thing here, by construction.** `findWindowId`
/// needs a running `flutter3d_modeler` window for `window_id.swift` to find,
/// and `capture` needs `screencapture`'s own screen-recording permission —
/// neither exists in this sandbox. What *is* tested (`window_capture_test.dart`)
/// is the command each method builds — the executable, the arguments, in
/// order — through a fake [ProcessRunner]; the real subprocess calls need a
/// real macOS run with the app open to confirm.
final class WindowCapture {
  const WindowCapture({required this.windowIdScript, this.run = Process.run});

  /// Path to `tool/tutorial/window_id.swift` — `bin/shoot.dart` resolves this
  /// from its own location so the tool works regardless of the caller's
  /// current directory.
  final String windowIdScript;

  final ProcessRunner run;

  /// Runs `swift <windowIdScript> <processName>` and parses its one line of
  /// stdout as the window id. Throws a [StateError] naming the process on a
  /// non-zero exit — no window found, or `swift` itself missing — rather
  /// than returning a sentinel a caller could shoot a blank screenshot with.
  Future<int> findWindowId(String processName) async {
    final result = await run('swift', <String>[windowIdScript, processName]);
    if (result.exitCode != 0) {
      throw StateError(
        'window_id.swift found no window for "$processName": '
                '${result.stderr}'
            .trim(),
      );
    }
    return int.parse((result.stdout as String).trim());
  }

  /// Saves window [windowId] to [outputPath] via `screencapture -x -l <id>`
  /// — `-x` for no shutter sound, `-l` to target one window rather than the
  /// whole screen. Creates [outputPath]'s parent directory first, since a
  /// case's own subdirectory under `cloud/server/web/assets/learn/modeler/`
  /// may not exist yet on a first run.
  Future<void> capture(int windowId, String outputPath) async {
    Directory(File(outputPath).parent.path).createSync(recursive: true);
    final result = await run('screencapture', <String>[
      '-x',
      '-l',
      '$windowId',
      outputPath,
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'screencapture failed for window $windowId: ${result.stderr}'.trim(),
      );
    }
  }
}
