/// What a game on this engine is as an application.
///
/// Not the simulation — that is `flutter3d_game` and the three genre packages.
/// This is the part in between that every one of the three games turned out to
/// have written for itself: the seam a rendered frame reaches Flutter through,
/// the run being played, and — since `flutter3d_screens` folded in here by the
/// package-merge plan — the screens a player uses before and after playing:
/// settings, volumes, rebinding, credits, and where a save is kept.
///
/// **The two used to be separate because neither of two neighbours could hold
/// both.** A session reads a level (which needs `flutter3d_bridge`, and
/// therefore the renderer) and writes a save (which needs storage); growing
/// `flutter3d_bridge` to hold storage, or a save's own package to hold a level,
/// was never the honest answer. A package depending on both, reached through
/// neither, was — and once that package existed, keeping the screens in a
/// package of their own bought nothing further: nothing outside this one ever
/// depended on `flutter3d_screens` without also depending on this package.
///
/// **What is deliberately not here.**
///
/// * *The title card and the screen a player sees when they lose.* Those are
///   the face of a particular game, and three identical title screens would be
///   a loss rather than a saving.
/// * *`backend.dart` and its two halves*, which all three games carry and which
///   are near enough byte-identical. The conditional import there chooses
///   between `flutter3d_impeller` and `flutter3d_webgl`, so a shared copy would
///   have to depend on both — against the decision written into `flutter3d.dart`
///   itself: "an application picks one and depends on one by name". Three files
///   of a dozen lines is cheaper than every game carrying both backends.
/// * *A state-management choice.* [RunSession] is an ordinary class. Two of the
///   three games wrap it in a cubit; a package that made that decision for them
///   would be a package deciding something it cannot see.
library;

// src/screens/* are the screens a player uses before and after playing —
// folded in from `flutter3d_screens` by the package-merge plan, each moved
// in unchanged apart from its own imports. Sorted alphabetically with
// everything else, per `directives_ordering`, rather than grouped apart.
export 'src/bug_report.dart';
export 'src/demo_timeline.dart';
export 'src/did_not_start.dart';
export 'src/frame_clock.dart';
export 'src/frame_timing_log.dart';
export 'src/run_session.dart';
export 'src/run_timeline.dart';
export 'src/run_timeline_extensions.dart';
export 'src/scene_surface.dart';
export 'src/screens/automap_view.dart';
export 'src/screens/clock_text.dart';
export 'src/screens/credits.dart';
export 'src/screens/demo_file.dart';
export 'src/screens/drag_look.dart';
export 'src/screens/owned_bindings.dart';
export 'src/screens/pad_presses.dart';
export 'src/screens/rebinding.dart';
export 'src/screens/save_file.dart';
export 'src/screens/settings_cubit.dart';
export 'src/screens/settings_file.dart';
export 'src/screens/settings_keys.dart';
export 'src/screens/settings_overlay.dart';
export 'src/screens/settings_panel.dart';
export 'src/screens/status_screens.dart';
export 'src/screens/storage/storage.dart';
export 'src/screens/tap_to_restart.dart';
export 'src/screens/touch_platform.dart';
export 'src/screens/volumes.dart';
export 'src/widget_surface.dart';
export 'src/widget_surface_pipeline.dart';
export 'src/widget_texture.dart';
