/// `HR5`'s Play button: a game the editor *starts*, where it can.
///
/// **A desktop runs the project with `flutter run`; a browser cannot run
/// anything.** Starting a game is a process, and a page has none to give —
/// so the web build's Play is the other half of `HR5`, a game somebody
/// started themselves and the editor attaches to by its VM service address
/// (`AttachedRun`). The button stays, and what it says on the web is how to
/// get there, because a Play button that silently did nothing would be the
/// worst of the three choices.
///
/// The process half lives behind a conditional import because
/// `package:flutter3d_editor_play/flutter3d_editor_play.dart` reaches
/// `dart:io` through `FlutterRun` and `flutterDevices`; `attach.dart` is the
/// part of that package a browser can compile, and is all `main.dart` names.
library;

export 'play_launch_io.dart'
    if (dart.library.js_interop) 'play_launch_web.dart';
