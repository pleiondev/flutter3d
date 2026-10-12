/// What any Flutter application on flutter3d is assembled from, in one import.
///
///     import 'package:flutter3d_app/flutter3d_app.dart';
///
///     final device = await openDevice(width: 1280, height: 720);
///     final renderer = Renderer.create(device: device);
///     // ... SceneSurface, presentFrame, LevelLoader, WidgetSurface, Storage
///
/// **Universal, and that is the test for a place here.** The modeller, the
/// level editor, the lessons and every game use what is below, and nothing
/// here knows what a run, a binding or a monster is. What a game adds on top —
/// the devices it is played with, the run, its settings screens, the actors
/// and fixtures its simulation moves — is `flutter3d_game`, which stands on
/// this package.
///
/// * **The backend choice.** `openDevice` and `presentFrame` look a backend up
///   in `flutter3d_hardware`'s own device registry, with the runtime fallback
///   to software when Impeller will not start. Each backend registers itself,
///   so a new one costs this file nothing.
/// * **The surface.** [SceneSurface] hands a rendered frame to Flutter; its
///   settings are a function called per frame, so anything derived from where
///   the camera ended up is derived after it got there. [FrameClock],
///   [FrameTimingLog], [DidNotStart] and the status screens are pacing, the
///   numbers a frame panel shows, and what an application says when it cannot
///   draw or cannot read its level.
/// * **Widgets in the scene.** [WidgetSurface] draws a Flutter widget onto a
///   quad the scene holds, and [WidgetSurfaceVisuals] builds one for each
///   `widget_surface` a level names.
/// * **A level loaded into a scene.** [LevelLoader] turns a level document into
///   mesh nodes, lights, probes and a collision world, with [SharedMeshes] and
///   [VisibilityCuller] beside it. An editor draws the level it is editing with
///   the same code a game plays it with.
/// * **Storage, and what a document says when it cannot be read.** [Storage]
///   and [BinaryStorage] keep a document where each platform keeps such
///   things, and an [Issue] is handed back rather than thrown.
///
/// * **XR and AR.** [XrSession] is the one boundary to a headset's or a
///   phone's runtime, and `Flutter3dView(xr:)` drives one: the runtime's
///   display time as the loop's clock, its poses on the tape, its views as
///   the frame's, and what was drawn back to it as layers ([XrDriver]).
///
/// `package:flutter3d_app/native.dart` holds the one piece that needs a
/// filesystem, off this barrel so a `dart:io` import never stops a web build
/// compiling, and `package:flutter3d_app/xr_testing.dart` the session a test
/// drives with no headset.
library;

export 'package:flutter3d_cpu/flutter3d_cpu.dart'
    show
        CpuFragmentShader,
        CpuVertexShaderByIndex,
        FragmentContext,
        ShaderBindings;
export 'package:flutter3d_level_scene/flutter3d_level_scene.dart'
    show LevelBatching;
export 'package:flutter3d_particles/flutter3d_particles.dart'
    show
        Flipbook,
        FlipbookCell,
        Particle,
        ParticleBirth,
        ParticleEffect,
        ParticleEmitter,
        ParticleSystem,
        Range;
export 'package:flutter3d_physics/flutter3d_physics.dart'
    show CollisionWorld, PhysicsBackend;
export 'package:flutter3d_sim/flutter3d_sim.dart'
    show
        Brush,
        DisplayTime,
        EngineLoop,
        EntityDef,
        EntityKind,
        EntityRegistry,
        FrameCadence,
        HeightfieldTiles,
        InputAction,
        InputState,
        Level,
        LevelMaterial,
        LevelVisibility,
        Lightmap,
        LightmapLayout,
        ShadowCasting,
        SimulationFactory,
        SimulationHandle,
        TileLevelChooser,
        TimeSource,
        WorldTiming,
        XrHand;

export 'src/backend_native.dart'
    if (dart.library.js_interop) 'src/backend_web.dart'
    show fixedResolution, openDevice, platformDevices, presentFrame;
export 'src/declarative/scene_widgets.dart';
export 'src/diagnostics/issues.dart';
export 'src/diagnostics/render_extensions.dart';
export 'src/diagnostics/render_inspection.dart';
export 'src/hot_swap/hot_swap.dart';
export 'src/l10n/app_localizations.dart';
export 'src/level/level_loader.dart';
export 'src/level/model_visuals.dart';
export 'src/level/prop_visuals.dart';
export 'src/level/shared_meshes.dart';
export 'src/level/terrain_tiles.dart';
export 'src/level/visibility_culler.dart';
export 'src/materials/material_language_stage.dart';
export 'src/photo/photo_shelf.dart';
export 'src/storage/storage.dart';
export 'src/surface/did_not_start.dart';
export 'src/surface/frame_clock.dart';
export 'src/surface/frame_timing_log.dart';
export 'src/surface/memory_pressure.dart';
export 'src/surface/scene_semantics.dart';
export 'src/surface/scene_surface.dart';
export 'src/surface/status_screens.dart';
export 'src/view/flutter3d_view.dart';
export 'src/view/frame_info.dart';
export 'src/view/probe_builder.dart';
export 'src/view/view_settings.dart'
    show
        DeviceLostEvent,
        DeviceSettings,
        LoopSettings,
        PluginSettings,
        SeatInput,
        SimulationPlacement,
        ViewSettings;
export 'src/widget_surface/widget_surface.dart';
export 'src/widget_surface/widget_surface_pipeline.dart';
export 'src/widget_surface/widget_surface_visuals.dart';
export 'src/widget_surface/widget_texture.dart';
export 'src/xr/xr_anchor.dart';
export 'src/xr/xr_driver.dart';
export 'src/xr/xr_layers.dart';
export 'src/xr/xr_session.dart';
export 'src/xr/xr_swapchain.dart';
