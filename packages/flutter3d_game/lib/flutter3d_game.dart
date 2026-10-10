/// What a game on flutter3d adds to an application: the devices it is played
/// with, the run being played, the settings and saves a player keeps, and
/// what a level's simulation moves, drawn.
///
/// **The one facade of the engine.** It re-exports `flutter3d`; from
/// `flutter3d_app` what a first game opens a window with — [Flutter3dView],
/// which opens the device, makes the renderer, runs the loop and owns focus
/// and the lifecycle, the [Flutter3dEngine] it hands a game, and
/// [LevelLoader]; and, by name, the level, the step loop and its input from
/// `flutter3d_sim`, the collision world from `flutter3d_physics` and the
/// listener and emitters from `flutter3d_audio_core` — so a first game takes
/// two imports, Flutter's `material.dart` and this, and no `hide`. No other
/// package of the engine re-exports another's API to save an import
/// (`tool/structure.dart` holds the list). The low level under the view
/// (opening a device, presenting a frame, `SceneSurface`, the frame clock)
/// is `flutter3d_app`'s, for the game that needs it, and is not re-exported
/// here. Everything else in `flutter3d_app`, `flutter3d_sim` and the physics
/// stays theirs: a file that needs more imports them, and its package
/// depends on them. The modeller and the lessons use those and never this
/// one, which is the line this package exists to draw.
///
/// * **Input that has forgotten which device it came from**: [DesktopInput],
///   [PadInput] and the [ActionMap] between a device and a `GameAction`, with
///   [Accommodations] and [GameSettings] beside them.
/// * **The run.** [RunSession] loads a level, restarts it, moves to the next,
///   saves and resumes; [RunTimeline] scrubs and branches what a run has
///   recorded, and [registerTimelineExtensions] lets a tool attached to a
///   running game ask it to.
/// * **What a player keeps**: [GameSettings] and the
///   [GameSettingsController] that writes it, [Rebinding], and the files
///   [SaveFile], [SettingsFile] and [DemoFile].
/// * **What a level's simulation moves, drawn**: [ActorVisuals] and
///   [FixtureVisuals], with the look decided by the game through
///   [ActorAppearance] and [FixtureAppearance], and [SoundOcclusion] for a wall
///   between a listener and a source.
/// * **The walk a level starts with**: [LevelWalk], a body that collides,
///   jumps and runs, turns where it is dragged and carries a camera at eye
///   height, and [openRegistryFor], which accepts every type a level names
///   before a game has taught it any.
///
/// **What is deliberately not here**: widgets. The touch controls, the
/// settings panel, the credits, the automap and every screen around a game
/// are `flutter3d_game_ui`'s, which stands on this package; this one names
/// none of them, so a test or a replaying server that reads the settings and
/// the run resolves no screen. Nor is there a state-management choice for the
/// run — [RunSession] is an ordinary class.
library;

export 'package:flutter3d/flutter3d.dart';
export 'package:flutter3d_app/flutter3d_app.dart'
    show
        DidNotStart,
        Flutter3dEngine,
        Flutter3dView,
        FrameInfo,
        LevelLoader,
        ListenerPose,
        LoadedLevel,
        SharedMeshes,
        ViewResolution;
// What a first game reaches for beyond drawing (§E.14 of
// `tasks/1.0-api-review.md`): the level, the step loop and its input from
// the simulation, the collision world from the physics, and the scene's
// listener and emitters from the audio. Named, so that a type added to any
// of the three is this facade's only once it is listed here; a game that
// needs more of one imports that package and depends on it.
export 'package:flutter3d_audio_core/flutter3d_audio_core.dart'
    show AudioEmitter, AudioListener, AudioScene, SoundBank, SoundDef;
export 'package:flutter3d_physics/flutter3d_physics.dart'
    show Collider, CollisionWorld, RigidDynamics;
export 'package:flutter3d_sim/flutter3d_sim.dart'
    show
        EngineLoop,
        EntityDef,
        InputState,
        Level,
        LevelCollision,
        LevelFormatException,
        LevelMaterial;

export 'src/cloud/cloud_save_store.dart';
export 'src/cloud/consents.dart';
export 'src/cloud/http_cloud_saves.dart';
export 'src/cloud/platform_cloud_saves.dart';
export 'src/cloud/save_sync.dart';
export 'src/config/accommodations.dart';
export 'src/config/color_roles.dart';
export 'src/config/color_vision_setting.dart';
export 'src/config/game_config.dart';
export 'src/config/high_contrast_setting.dart';
export 'src/game_formats.dart';
export 'src/input/action_input.dart';
export 'src/input/action_map.dart';
export 'src/input/bindings.dart';
export 'src/input/desktop_input.dart';
export 'src/input/pad_actions.dart';
export 'src/input/playing.dart';
export 'src/run/actor_animations.dart';
export 'src/run/autosave.dart';
export 'src/run/bug_report.dart';
export 'src/run/demo_recording.dart';
export 'src/run/demo_timeline.dart';
export 'src/run/game_events.dart'
    show ToolEventPoster, postToolEvent, toolEventPrefix;
export 'src/run/level_asset.dart';
export 'src/run/live_level.dart';
export 'src/run/replay_after_swap.dart';
export 'src/run/run_session.dart';
export 'src/run/run_timeline.dart';
export 'src/run/run_timeline_extensions.dart';
export 'src/screens/clock_text.dart';
export 'src/screens/demo_file.dart';
export 'src/screens/drag_look.dart';
export 'src/screens/game_settings.dart';
export 'src/screens/pad_presses.dart';
export 'src/screens/rebinding.dart';
export 'src/screens/save_file.dart';
export 'src/screens/settings_file.dart';
export 'src/screens/settings_keys.dart';
export 'src/screens/touch_platform.dart';
export 'src/screens/volumes.dart';
export 'src/visuals/actor_visuals.dart';
export 'src/visuals/behaviour_overlay.dart';
export 'src/visuals/fixture_visuals.dart';
export 'src/visuals/outline_marks.dart' show outlineColorOf;
export 'src/visuals/sound_occlusion.dart';
export 'src/walk/level_walk.dart';
