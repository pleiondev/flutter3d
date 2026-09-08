/// Which backend this build draws through.
///
///     import 'package:flutter3d_backend/flutter3d_backend.dart';
///
///     final device = await openDevice(width: 1280, height: 720);
///
/// The engine talks to `flutter3d_hardware` and never to a graphics API, so
/// something has to pick — and this is that something. **Three decisions, not
/// one, and they are made three different ways:**
///
/// * **Web or native** is a conditional export, decided at compile time,
///   because the two pull in incompatible worlds: `flutter_gpu` does not
///   compile for the web and `dart:js_interop` does not compile for macOS, so a
///   file that imported both could target neither.
/// * **Impeller or software**, on the native half, is a `try`/`catch` at
///   runtime, because `flutter_gpu` ships with the SDK and is always
///   importable — whether it actually *starts* depends on the platform and how
///   the engine was launched, which nothing at compile time can see.
/// * **WebGPU or WebGL2**, on the browser half, is the same `try`/`catch` — a
///   browser's `navigator.gpu`, and the adapter it may refuse to hand out on a
///   blocklisted driver, are not visible to a compiler either — but it is
///   reached only when a build says `--dart-define=FLUTTER3D_WEBGPU=true`. The
///   define is there because trying both means shipping both, and an ordinary
///   web build has no reason to carry a second backend it will not open. The
///   flag's own doc in `backend_web.dart` is where that trade is written out.
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
