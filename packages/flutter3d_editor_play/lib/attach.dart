/// The half of Play a browser can run: a game somebody else started,
/// attached to by its VM service address, with its console, the events it
/// posts, its hot reload and restart, and a saved level sent to it.
///
/// **No `dart:io` anywhere under it**, which `test/attach_web_test.dart`
/// checks, since a web build compiles with `dart:io` in it and fails only
/// when it is called: the web editor imports this and not
/// `flutter3d_editor_play.dart`, whose `FlutterRun` starts a process a
/// browser does not have.
library;

export 'src/attached_run.dart';
export 'src/game_events.dart';
export 'src/level_push.dart';
export 'src/play_state.dart';
export 'src/vm_connect.dart';
export 'src/watched.dart';
