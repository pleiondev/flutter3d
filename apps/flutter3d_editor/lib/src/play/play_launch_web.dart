/// Play by process, in a browser: none — see `play_launch.dart`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_editor_play/attach.dart';

/// Whether this build can start a game, rather than only attach to one.
const bool kStartsGames = false;

/// Why a level cannot be played here, which is always: the answer is the
/// way to Play that does work.
String? whyCannotPlay(String levelPath) =>
    'a browser cannot start a game — run it yourself (flutter run) and '
    'attach to the VM service address it prints, with the button at the '
    'top right';

/// Never reached: [whyCannotPlay] always answers.
PlayedGame gameFor(String levelPath, PlayedGame? current) =>
    throw UnsupportedError(whyCannotPlay(levelPath)!);

/// A game attached to has no device to pick.
Widget Function({required bool enabled})? devicePickerFor(PlayedGame game) =>
    null;
