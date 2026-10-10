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
/// Here rather than in `flutter3d_app`, which holds only what every
/// application uses — the modeller and the lessons among them — and a phone
/// locked to landscape is a game's decision, the same kind of not-the-game
/// screen concern as everything else in this package.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../input/playing.dart';

/// Locks to landscape and hides the system bars, on a device played by touch
/// — [playing] says whether this one is, and is the platform's own answer
/// when not given.
///
/// **An application's choice, called from its `main()` and nowhere else.**
/// Nothing in the engine calls it: whether a game is landscape only is the
/// game's to decide, and a game in portrait, or one that is a page inside a
/// larger app, simply does not call this. It was `configureForTouch`, a name
/// that sounded like setup every game needed; it is named for what it does.
///
/// Does nothing on a device not played by touch, so it is safe to call
/// unconditionally from `main()` — which is the point, because the guard is
/// exactly what the racing game was missing rather than the calls.
///
/// `ensureInitialized` because both calls are platform channels, and a channel
/// before the binding exists is an assertion rather than an effect.
///
/// `immersiveSticky` rather than `edgeToEdge`: the bars go away and a swipe
/// brings them back as an overlay that fades, rather than pushing the game's
/// layout about every time somebody reaches for a corner.
///
/// Fires the two calls and does not wait for them, so `main()` stays
/// synchronous — a `runApp` that waited on a platform channel would show
/// nothing until the operating system answered.
void lockLandscapeForTouch([Playing? playing]) {
  if (!(playing ?? Playing.ofPlatform()).touch) return;
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).ignore();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky).ignore();
}
