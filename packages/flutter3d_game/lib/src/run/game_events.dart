import 'dart:developer' as developer;

/// Posts what happened in a game, to whoever watches it from outside: the
/// shape of [postToolEvent], and of what a test hears it through.
typedef ToolEventPoster = void Function(String kind, Map<String, Object?> data);

/// What every kind a game posts is prefixed with on the VM service.
const String toolEventPrefix = 'flutter3d.';

/// Tells a tool listening on the game's VM service — the editor's Play
/// panel, an agent's `play_events` — that something happened: a level is
/// up, the player died, a pickup was taken.
///
/// Posted as `developer.postEvent('flutter3d.<kind>', data)` on the VM
/// service's `Extension` stream, which is where `flutter3d_editor_play`
/// listens, keeping only the kinds with [toolEventPrefix]. [kind] is written
/// without it, dotted from the general to the particular — `level.loaded`,
/// `player.died` — and [data] has to be JSON: strings, numbers, booleans,
/// null, and lists and maps of those.
///
/// **Not a second event system.** A step's events are for the game itself
/// and go through its bus; this is for the handful of moments somebody
/// watching the game from outside wants to hear about, and it costs nothing
/// when nobody is listening: `postEvent` with no VM service to send it to,
/// which is every release build, goes nowhere.
///
/// A test hears what was posted with `captureToolEvents` from
/// `package:flutter3d_game/testing.dart`.
void postToolEvent(String kind, Map<String, Object?> data) {
  final heard = toolEventCapture;
  if (heard != null) {
    heard(kind, data);
    return;
  }
  developer.postEvent('$toolEventPrefix$kind', data);
}

/// Where [postToolEvent] posts while a test listens; null posts to the VM
/// service. Set only through `captureToolEvents` in `testing.dart`, which is
/// the one library that exports it.
ToolEventPoster? toolEventCapture;
