/// The layer an application is assembled from, in one import.
///
///     import 'package:flutter3d_app/flutter3d_app.dart';
///
///     final device = await openDevice(width: 1280, height: 720);
///     // ... SceneSurface, RunSession, SettingsOverlay, Gamepad, PointerLock —
///     // all reachable from here.
///
/// Four packages, plus the backend choice this one now makes directly, exist
/// because the wiring they hold was written out, close to identically, in
/// three `main.dart` files before any of them existed:
///
/// * **The backend choice** — which backend a build draws through, and the
///   runtime fallback to software if Impeller will not start — used to be its
///   own package, `flutter3d_backend`. It moved here because most of its
///   consumers already reached it through this barrel rather than by naming
///   it, and the handful that still named it directly cost nothing to
///   repoint, which left nothing for a separate package to be the boundary of.
/// * `flutter3d_session` — `SceneSurface`, the widget that hands a frame to
///   Flutter, and `RunSession`, a level's load/restart/save/advance sequence.
/// * `flutter3d_screens` — the settings, rebinding and save screens no game owns.
/// * `pad_input` — a gamepad, read once per frame.
/// * `pointer_lock` — desktop mouse capture, for an FPS-style camera.
///
/// None of the four sibling packages know about each other, and this package
/// does not change that — it re-exports them, and holds only the backend
/// choice as code of its own. What it buys is that an application says "the
/// assembly layer" once, the same way importing `flutter3d` says "the
/// renderer" once instead of naming `flutter3d_hardware`.
///
/// **Not behind this barrel:** `flutter3d`, `flutter3d_bridge`,
/// `flutter3d_game`, and a genre package. Those are content — what a scene
/// looks like and what kind of game this is — and a facade cannot choose a
/// genre on an application's behalf.
library;

export 'src/backend_native.dart'
    if (dart.library.js_interop) 'src/backend_web.dart'
    show kFixedResolution, openDevice;
export 'package:flutter3d_screens/flutter3d_screens.dart';
export 'package:flutter3d_session/flutter3d_session.dart';
export 'package:pad_input/pad_input.dart';
export 'package:pointer_lock/pointer_lock.dart';
