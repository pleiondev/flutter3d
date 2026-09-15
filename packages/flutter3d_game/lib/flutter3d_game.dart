/// What a game on flutter3d adds to an application: the devices it is played
/// with, the run being played, the screens a player uses that are not the
/// game, and what a level's simulation moves, drawn.
///
/// **It stands on `flutter3d_app` and `flutter3d_sim`, and re-exports
/// neither.** A file that loads a level or opens a device imports
/// `flutter3d_app`; one that steps a simulation imports `flutter3d_sim`; one
/// that reads a touch stick or saves a run imports this. The modeller and the
/// lessons use the first two and never this one, which is the line this
/// package exists to draw.
///
/// * **Input that has forgotten which device it came from**: [TouchControls],
///   [DesktopInput], [PadInput] and the [Bindings] between a device and a
///   `GameAction`, with [Accommodations] and [GameConfig] beside them.
/// * **The run.** [RunSession] loads a level, restarts it, moves to the next,
///   saves and resumes; [RunTimeline] scrubs and branches what a run has
///   recorded, and [registerTimelineExtensions] lets a tool attached to a
///   running game ask it to.
/// * **The screens that are not the game**: [SettingsOverlay] with volumes,
///   gamepad and accessibility sliders and a rebinding list, [SaveFile],
///   [SettingsFile] and [DemoFile], [AutomapView], [TapToRestart] and the
///   credits. What a particular game says is passed in: the credits are a
///   widget, and the rebindable actions are the caller's.
/// * **What a level's simulation moves, drawn**: [ActorVisuals] and
///   [FixtureVisuals], with the look decided by the game through
///   [ActorAppearance] and [FixtureAppearance], and [SoundOcclusion] for a wall
///   between a listener and a source.
///
/// **What is deliberately not here**: the title card and the loss screen,
/// which are the face of a particular game, and a state-management choice for
/// the run — [RunSession] is an ordinary class.
library;

export 'src/config/accommodations.dart';
export 'src/config/game_config.dart';
export 'src/input/bindings.dart';
export 'src/input/desktop_input.dart';
export 'src/input/pad_actions.dart';
export 'src/input/playing.dart';
export 'src/input/touch_controls.dart';
export 'src/run/bug_report.dart';
export 'src/run/demo_timeline.dart';
export 'src/run/run_session.dart';
export 'src/run/run_timeline.dart';
export 'src/run/run_timeline_extensions.dart';
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
export 'src/screens/tap_to_restart.dart';
export 'src/screens/touch_platform.dart';
export 'src/screens/volumes.dart';
export 'src/visuals/actor_visuals.dart';
export 'src/visuals/fixture_visuals.dart';
export 'src/visuals/sound_occlusion.dart';
