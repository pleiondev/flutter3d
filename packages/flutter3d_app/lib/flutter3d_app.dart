/// The layer an application is assembled from, in one import.
///
///     import 'package:flutter3d_app/flutter3d_app.dart';
///
///     final device = await openDevice(width: 1280, height: 720);
///     // ... SceneSurface, RunSession, SettingsOverlay, Gamepad, PointerLock —
///     // all reachable from here.
///
/// Five packages exist because the wiring they hold was written out, close to
/// identically, in three `main.dart` files before any of them existed:
///
/// * `flutter3d_backend` — which backend a build draws through, and the
///   runtime fallback to software if Impeller will not start.
/// * `flutter3d_session` — `SceneSurface`, the widget that hands a frame to
///   Flutter, and `RunSession`, a level's load/restart/save/advance sequence.
/// * `flutter3d_screens` — the settings, rebinding and save screens no game owns.
/// * `pad_input` — a gamepad, read once per frame.
/// * `pointer_lock` — desktop mouse capture, for an FPS-style camera.
///
/// None of the five know about each other, and this package does not change
/// that — it re-exports, and holds no code of its own. What it buys is that an
/// application says "the assembly layer" once, the same way importing
/// `flutter3d` says "the renderer" once instead of naming `flutter3d_hardware`.
///
/// **Not behind this barrel:** `flutter3d`, `flutter3d_bridge`,
/// `flutter3d_game`, and a genre package. Those are content — what a scene
/// looks like and what kind of game this is — and a facade cannot choose a
/// genre on an application's behalf.
library;

export 'package:flutter3d_backend/flutter3d_backend.dart';
export 'package:flutter3d_screens/flutter3d_screens.dart';
export 'package:flutter3d_session/flutter3d_session.dart';
export 'package:pad_input/pad_input.dart';
export 'package:pointer_lock/pointer_lock.dart';
