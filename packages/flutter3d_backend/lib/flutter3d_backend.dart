/// Which backend this build draws through.
///
///     import 'package:flutter3d_backend/flutter3d_backend.dart';
///
///     final device = await openDevice(width: 1280, height: 720);
///
/// The engine talks to `flutter3d_graphics` and never to a graphics API, so
/// something has to pick — and this is that something. A conditional export
/// rather than a runtime branch, because the two backends pull in incompatible
/// worlds: `flutter_gpu` does not compile for the web and `dart:js_interop`
/// does not compile for macOS, so a file that imported both could target
/// neither.
///
/// ## What it does not decide
///
/// **Resolution and shadow budget stay in the application.** The racing game
/// draws its browser build at 960×540 with two 1024 shadow tiles and says why
/// in its own file; the other two draw at 720p with the desktop's atlas. That is
/// a game's trade against its own scene, not a property of a backend, and a
/// shared constant would be a number that is wrong for two of the three.
///
/// What is shared is the part that was genuinely the same: the choice, and
/// [openDevice]. Those were three files in three games, byte-identical in two of
/// them down to the paragraph explaining the conditional import.
library;

export 'src/backend_native.dart'
    if (dart.library.js_interop) 'src/backend_web.dart'
    show kFixedResolution, openDevice;
