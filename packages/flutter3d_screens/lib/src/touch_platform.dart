/// What a game asks of the operating system when it is played with fingers.
///
/// **Two of the three applications did this and the third did not**, which is
/// what a copied `main()` looks like after a while: the crypt and the
/// platformer each locked to landscape and hid the system bars, and the racing
/// game — which has touch controls and is meant to run on a phone — did
/// neither. A racer that reframes its chase camera because somebody tilted the
/// handset, with the status bar over the lap counter, is not a bug anybody
/// would file; it is a game that feels wrong.
///
/// Here rather than in `flutter3d_app`, which says in its own first paragraph
/// that it re-exports and holds no code: this is code, and it is the same kind
/// of not-the-game screen concern as everything else in this package.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d_game/flutter3d_game.dart' show Playing;

/// Locks to landscape and hides the system bars, on a device played by touch.
///
/// Does nothing anywhere else, so it is safe to call unconditionally from
/// `main()` — which is the point, because the guard is exactly what the racing
/// game was missing rather than the calls.
///
/// `ensureInitialized` because both calls are platform channels, and a channel
/// before the binding exists is an assertion rather than an effect.
///
/// `immersiveSticky` rather than `edgeToEdge`: the bars go away and a swipe
/// brings them back as an overlay that fades, rather than pushing the game's
/// layout about every time somebody reaches for a corner.
///
/// Returns the futures rather than awaiting them, so `main()` stays
/// synchronous — a `runApp` that waited on a platform channel would show
/// nothing until the operating system answered.
void configureForTouch() {
  if (!Playing.touch) return;
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).ignore();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky).ignore();
}
