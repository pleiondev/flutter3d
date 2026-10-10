/// What a test of a game reaches for and a game does not: hearing what the
/// game told the tools watching it.
library;

import 'src/run/game_events.dart';

export 'src/run/game_events.dart' show ToolEventPoster;

/// Sends everything [postToolEvent] posts to [heard] instead of the VM
/// service, until the returned function is called, which puts the VM
/// service back.
///
/// ```dart
/// final posted = <String>[];
/// addTearDown(captureToolEvents((kind, data) => posted.add(kind)));
/// ```
void Function() captureToolEvents(ToolEventPoster heard) {
  final before = toolEventCapture;
  toolEventCapture = heard;
  return () => toolEventCapture = before;
}
