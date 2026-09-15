/// A modeller for flutter3d.
///
///     flutter run -d macos
///     flutter run -d chrome --dart-define=model=assets/models/DamagedHelmet.glb
///
/// **The spike, and it is honest about being one.** What is here opens a device
/// through `flutter3d_app`, builds the one scene `staging.dart` assembles, and
/// orbits it: a cube by default, or whatever `--dart-define=model=` names. What
/// is not here is the modeller — the document, the commands, the history, the
/// panels — and it is not here because the question this build exists to answer
/// comes first: does a viewport with a real model in it hold sixty frames on a
/// laptop and in a browser, and does the whole thing build for `--wasm`.
///
/// The answers, with the machine and the date beside them, go in
/// `doc/model-editor.md` §6. The plan this follows is `doc/model-editor-plan.md`
/// — ui-00 for this file, view-02 for the viewport, p0-01 for the measurements.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show AppExitResponse, PlatformDispatcher;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'l10n/app_localizations.dart';
import 'src/animation_wiring.dart';
import 'src/app_config.dart';
import 'src/autosaving.dart';
import 'src/cabinet_link.dart';
import 'src/churn_run.dart';
import 'src/close_beforeunload.dart';
import 'src/close_guard.dart';
import 'src/crash_handling.dart';
import 'src/display_modes.dart';
import 'src/element_picker_cache.dart';
import 'src/element_picking.dart';
import 'src/environment_summary.dart';
import 'src/exporting.dart';
import 'src/files/cabinet_save.dart';
import 'src/files/fetch_model.dart';
import 'src/files/file_drop.dart';
import 'src/files/preview_capture.dart';
import 'src/files/project_files.dart';
import 'src/files/sandbox_probe.dart';
import 'src/ground_grid.dart';
import 'src/import_plan.dart';
import 'src/input_policy.dart';
import 'src/material_editing.dart';
import 'src/material_pool.dart' show clay;
import 'src/mcp_bootstrap.dart';
import 'src/measurement_runs.dart';
import 'src/modeler_cubit.dart';
import 'src/modeler_ui_actions.dart';
import 'src/modeler_viewport.dart';
import 'src/object_picking.dart';
import 'src/open_report.dart';
import 'src/opening.dart';
import 'src/orbit_run.dart';
import 'src/orientation_dial.dart';
import 'src/recent_projects.dart';
import 'src/report_problem.dart';
import 'src/selection_box.dart';
import 'src/selection_rules.dart';
import 'src/shape_key_state.dart';
import 'src/shape_points_overlay.dart';
import 'src/staging.dart';
import 'src/timeline_preview_wiring.dart';
import 'src/tool_commands.dart';
import 'src/transform_dispatch.dart';
import 'src/transform_fields.dart';
import 'src/transform_session.dart';
import 'src/ui/agent_session_panel.dart';
import 'src/ui/animation_bottom.dart';
import 'src/ui/autorig_dialog.dart';
import 'src/ui/bend_slider_bar.dart';
import 'src/ui/clip_library.dart';
import 'src/ui/clip_tracks_bar.dart';
import 'src/ui/export_anyway_dialog.dart';
import 'src/ui/export_screen.dart';
import 'src/ui/game_preview_screen.dart';
import 'src/ui/import_screen.dart';
import 'src/ui/lathe_dialog.dart';
import 'src/ui/material_studio_dialog.dart';
import 'src/ui/measurement_report_overlay.dart';
import 'src/ui/modeler_keys.dart';
import 'src/ui/properties/properties_panel.dart';
import 'src/ui/restore_autosave_dialog.dart';
import 'src/ui/retarget_panel.dart';
import 'src/ui/retarget_viewports.dart';
import 'src/ui/save_as_dialog.dart';
import 'src/ui/screen_parts.dart';
import 'src/ui/shell_for_width.dart';
import 'src/ui/shortcut_help_screen.dart';
import 'src/ui/start_screen.dart';
import 'src/ui/status_line.dart';
import 'src/ui/theme.dart';
import 'src/ui/tools.dart';
import 'src/ui/top_bar_actions.dart';
import 'src/ui/transport_bar.dart';
import 'src/ui/unsaved_changes_dialog.dart';
import 'src/ui/weight_legend.dart';
import 'src/viewport_metrics.dart';
import 'src/weight_gradient.dart';
import 'src/weight_paint_session.dart';

part 'src/screen/animation.dart';
part 'src/screen/app_wiring.dart';
part 'src/screen/autorig_wiring.dart';
part 'src/screen/close_and_recovery.dart';
part 'src/screen/device.dart';
part 'src/screen/files.dart';
part 'src/screen/game_preview_wiring.dart';
part 'src/screen/interactions.dart';
part 'src/screen/morphs_wiring.dart';
part 'src/screen/ready_parts.dart';
part 'src/screen/retarget_wiring.dart';
part 'src/screen/weight_paint_wiring.dart';

/// `ui-30n`: wires an exception nobody caught to the same response wherever
/// it surfaces. `FlutterError.onError` catches one the framework itself
/// caught mid-callback (a build, a gesture, a layout) and would otherwise
/// only dump to the console; `runZonedGuarded`'s own handler catches one that
/// got past that — thrown from a `Future` callback with nobody awaiting it,
/// say. Both call [_onUncaughtError] with the same two arguments, so a
/// command's `apply()` throwing lands the same emergency autosave and the
/// same dialog regardless of which door it went out.
void main() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    unawaited(
      _onUncaughtError(details.exception, details.stack ?? StackTrace.current),
    );
  };
  runZonedGuarded(
    () => runApp(const ModelerApp()),
    (Object error, StackTrace stack) =>
        unawaited(_onUncaughtError(error, stack)),
  );
}

class _ModelerScreenState extends State<ModelerScreen>
    with SingleTickerProviderStateMixin {
  /// The document and everything a screen rebuilds on. See
  /// `modeler_cubit.dart`: the orbit, the modal transform and the frame
  /// timings stay plain fields below, because they change while a finger is
  /// down and a rebuild of the shell per frame is not a thing this can afford.
  final ModelerCubit _cubit = ModelerCubit();

  ModelerState get _state => _cubit.state;

  /// The open document. Reading it through the cubit rather than holding a
  /// second reference is what stops the two disagreeing — the mistake this
  /// application already made once, between the scene and the project.
  ModelHistory get _history => (_state as ModelerReady).history;

  Ticker? _ticker;

  /// The measured camera orbit and the edit-convert-upload churn loop, when
  /// the build asked for either.
  final MeasurementRuns _measurementRuns = MeasurementRuns(
    what: kStress > 0
        ? '$kStress triangles in $kStressObjects draws'
        : (kModel.isEmpty ? 'the cube' : kModel),
  );

  /// What the last frame's `render` cost, which the run records against the
  /// wall clock the ticker reports.
  int? _lastRenderMicros;

  /// The device, kept so a model opened later can be uploaded through it.
  GraphicsDevice? _device;

  /// The viewport size and pixel ratio the current [_device] was opened at,
  /// so a later resize past that fixed canvas can be noticed.
  int _deviceWidth = 0;
  int _deviceHeight = 0;
  double _deviceDevicePixelRatio = 1;

  /// Set while a stale device is being swapped for a freshly sized one, so a
  /// second resize during the swap does not start a redundant reopen.
  bool _reopeningDevice = false;

  /// `tut-19`/`tut-20`'s own cabinet id/mode — [CabinetLink.none] until
  /// `_open()` reads `widget.cabinetLink` or, failing that, `Uri.base`'s own
  /// `id`/`mode`/`csrf`, the same place `model`/`name` already come from.
  /// Fixed for the life of one document: nothing later in a session changes
  /// which cabinet entry, if any, this build was opened from.
  CabinetLink _cabinetLink = CabinetLink.none;

  /// Where `_saveToCabinet` sends its POST — `widget.cabinetSourceSender`
  /// when a test supplied one, otherwise the platform's own real send.
  CabinetSourceSender get _sendCabinetSource =>
      widget.cabinetSourceSender ?? postSourceToCabinet;

  /// Where `tut-19`'s own preview capture sends its POST —
  /// `widget.previewCapturer` when a test supplied one, otherwise the
  /// platform's own real capture-and-send.
  PreviewCapturer get _sendPreviewCapture =>
      widget.previewCapturer ?? capturePreview;

  /// Whether `tut-19`'s own preview capture has already fired once this
  /// session — set the first time [_installOpened] sees a
  /// [CabinetLink.shouldCapturePreview] worth acting on, so a document
  /// opened locally afterward (a drag-drop, a recovered autosave) over a
  /// cabinet-viewed model never captures a picture of something that is not
  /// what the cabinet entry's id names. [_cabinetLink] itself never changes
  /// after `_open()` sets it, so this is the one latch a second
  /// [_installOpened] needs.
  bool _cabinetPreviewCaptured = false;

  /// What the last file operation said, shown beside the buttons.

  /// Which lens the viewport looks through, and what the surface is drawn as.
  ViewLens _lens = ViewLens.perspective;
  ShadingMode _shading = ShadingMode.material;

  /// Where a rotation or a scale from the transform panel is centred, and
  /// whose axes a rotation is given in.
  ///
  /// **Plain fields, the way [_lens] and [_shading] are.** Neither is part of
  /// the document — undoing to before a rotation does not put the pivot chip
  /// back where it was either — so there is nothing here for `ModelerCubit`
  /// to keep in step with a command landing.
  PivotChip _pivot = PivotChip.median;
  TransformSpace _space = TransformSpace.global;

  /// Which of the project's own lights `SceneSourcePanel` shows the fields
  /// of — `mat-34d`'s own scene-mode wiring. A plain field for the same
  /// reason [_pivot] is one: nothing on the document remembers which light a
  /// person was looking at, so undo has nothing to put this back to either.
  int? _selectedLight;

  /// `S2`'s own row: which clip, track, key, joint and constraint the
  /// animation mode's own panels highlight — see `screen/animation.dart`'s
  /// own `_AnimationWiring` for the setters. Plain fields for the same
  /// reason [_selectedLight] is one: none of them are on [ModelHistory], so
  /// undo has nowhere to put any of them back to.
  int? _selectedAnimationClip;
  int? _selectedAnimationTrack;
  int? _selectedAnimationKey;
  int? _selectedJoint;
  int? _selectedConstraint;

  /// `S6`'s own row: which shape key `MorphsPanel` highlights, and the
  /// marker the viewport's own shape-points overlay draws `secondary` for —
  /// a plain field for the same reason [_selectedLight] is one.
  int? _selectedShape;

  /// `S7`'s own row: screen 14's own retarget state — see `screen/
  /// retarget_wiring.dart`. Plain fields for the same reason [_selectedLight]
  /// is one: none of them are on [ModelHistory], so undo has nowhere to put
  /// any of them back to. `RetargetSource` itself is a whole second
  /// `ModelProject`, never folded into [_history]'s own.
  RetargetSource? _retargetSource;
  int? _retargetSourceClipIndex;
  BoneMap _retargetBoneMap = const BoneMap(<String, String>{});
  RetargetRootMotion _retargetRootMotion = RetargetRootMotion.inAnimation;
  bool _retargetLockFeet = true;
  double _retargetGroundY = 0.0;
  double _retargetFootTolerance = 1e-3;
  double _retargetBlendSeconds = 0.15;

  /// Which of the target's own clips `retarget.apply` last appended, and
  /// its name — null before anything has landed. `ClipTracksBar`'s own
  /// "nothing to preview yet" and `RetargetPanel.onRootMotionChanged`'s own
  /// "nothing landed yet to re-bake" both read this.
  int? _retargetAppliedClipIndex;
  String? _retargetAppliedClipName;

  /// The transport's own `Keys`/`Curves` switch — screen 07's own row, not
  /// on [ModelerReady] for the identical reason [_selectedAnimationClip]
  /// above is not.
  TimelineEditMode _timelineEditMode = TimelineEditMode.keys;

  /// `S5`'s own weight-paint brush: radius in logical pixels, strength 0 to
  /// 1, and the mirror/normalize flags a stroke reads the moment it opens —
  /// see `screen/weight_paint_wiring.dart`. Plain fields for the same reason
  /// [_selectedLight] is one: none of them are on [ModelHistory], so undo has
  /// nowhere to put any of them back to. `48`/`1.0` match the design
  /// hand-over's own screen 13.
  double _weightBrushRadius = 48.0;
  double _weightBrushStrength = 1.0;
  bool _weightMirror = false;
  bool _weightNormalize = true;

  /// The vertex nearest the weight brush's own last hit —
  /// `ui/weight_paint_panel.dart`'s own influences card.
  int? _selectedWeightVertex;

  /// `S5`'s own brush stroke controller — see `weight_paint_session.dart`.
  late final WeightPaintSession _weightPaintSession = WeightPaintSession(
    cubit: _cubit,
    history: () => _history,
    stage: () => (_state as ModelerReady).stage,
  );

  /// `S5`'s own viewport-preview material swap for the weights view — see
  /// `weight_gradient.dart`'s own class comment for why nothing calls it
  /// before this row.
  final WeightGradientShading _weightGradientShading = WeightGradientShading();

  /// The playhead, in whole frames — `S2`'s own `ValueNotifier<int>`.
  ///
  /// **Not a field on [ModelerState], and not moved by `setState` either.**
  /// [TimelinePlayback.onFrameChanged] fires up to sixty times a second
  /// while a clip plays; a `Cubit`'s `emit` at that rate would rebuild the
  /// whole shell for a number only the transport bar and the timeline's own
  /// playhead read, and `setState` on this screen would do the same for
  /// every other widget the `build` method below returns. The transport bar
  /// and `TimelinePanel`/`CurveEditor` read this through a
  /// `ValueListenableBuilder` instead — see `ui/animation_bottom.dart`.
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  /// Remembers what the materials were, so the normals view can be left.
  final SurfaceShading _surfaces = SurfaceShading();

  /// Which mode the interface is in, which level a mesh is edited at, and
  /// which tool is armed.
  ///
  /// Three fields on the state rather than a `ModelerCubit`, and only until
  /// `ui-03`: what that class is for is a *project* — a document, a history, a
  /// readiness — and standing one up around three enums would be a cubit that
  /// has to be rewritten the day it gets something to hold.
  ModelerMode get _mode => (_state as ModelerReady).mode;
  MeshSubmode get _submode => (_state as ModelerReady).submode;
  String? get _tool => (_state as ModelerReady).tool;

  /// The document, and everything that has been done to it.
  ///
  /// **One history for both modes**, which is what replaced the mesh-only
  /// session: ⌘Z now takes back a rename, a move of an object and an extrusion
  /// with the same press, in the order they were made. Two stacks would have
  /// meant a person undoing a move and getting an extrusion back.
  /// A project with the cube a new one starts as.
  static ModelProject _newProject() => const ModelProject().added(
    (int id) => ModelObject(
      id: id,
      name: 'cube',
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: vm.Matrix4.identity(),
    ),
  );

  /// The mesh being edited, when what is selected has one.
  ///
  /// One implementation, in the cubit, because the sub-mode change needs the
  /// same answer and two copies of "which mesh is being edited" is exactly the
  /// shape of the disagreement this application already had once.
  EditMesh? get _editMesh => editMeshOf(_history.project, _history.selection);

  /// The picker over that mesh, rebuilt when its version moves.
  final ElementPickerCache _elementPickerCache = ElementPickerCache();

  MeshPicker? get _elementPicker {
    final EditMesh? mesh = _editMesh;
    final int? id = _history.selection.activeObject;
    if (mesh == null || id == null) return null;
    return _elementPickerCache.pickerFor(mesh, _history.project[id]!.version);
  }

  /// The modal transform, the gizmo it shares a path with, and `view-26n`'s
  /// geometry snap — see `transform_session.dart`.
  late final TransformSession _transformSession = TransformSession(
    cubit: _cubit,
    history: () => _history,
    editMesh: () => _editMesh,
  );

  /// What the last operation said when it refused, shown in the status line
  /// until something else happens.

  /// The tick the last frame was at, so a turn advances by real time rather
  /// than by frames — a view that swings faster on a fast machine is a view
  /// nobody can aim.
  Duration _lastTick = Duration.zero;

  /// `anim-07`'s own live pose binding: whichever clip [AnimationPanel] has
  /// open, sampled onto the scene nodes [ModelerStage.sync] tracks — see
  /// `timeline_preview_wiring.dart`. `S2` wires its two hooks straight to
  /// [ModelerCubit.playback] (the coarse half) and [_frame] (the per-frame
  /// half) — see `screen/animation.dart`'s own class comment for why they
  /// are two different mechanisms rather than one.
  late final TimelinePreviewWiring _timelinePreview = TimelinePreviewWiring(
    onPlaybackChanged: _cubit.playback,
    onFrameChanged: (int frame) => _frame.value = frame,
  );

  /// [AnimationPanel.onTimeChanged].
  void _scrubAnimation(double time) {
    if (_state case ModelerReady(:final project, :final stage)) {
      _timelinePreview.scrub(project, stage.sync, time);
    }
  }

  /// What the finished run measured, shown over the viewport.
  ///
  /// **On the screen and not only in the console**, because the console is the
  /// one place half the platforms being measured do not have: a browser's is
  /// behind a keyboard shortcut and a handset's needs a cable. A panel in the
  /// corner is legible in a screenshot from any of them, which is what a
  /// measurement recorded in a document needs to have come from.
  String? _report;

  /// Build and raster times, printed when the build asked for them with
  /// `--dart-define=FLUTTER3D_TIMINGS=true`. Off otherwise, and off is not a
  /// half measure: the log costs a callback per frame and reports nothing.
  final FrameTimingLog _timings = FrameTimingLog(label: 'modeller');

  /// `ui-24`'s own window-close interception on desktop, where there is no
  /// `Navigator` route for `PopScope` to guard — the OS asks the app
  /// directly rather than routing a back gesture through one.
  late final AppLifecycleListener _lifecycle;

  /// `ui-18`'s own background writer. Watches `_cubit` from the moment this
  /// screen exists, not from whenever a document happens to open — the same
  /// `ModelerCubit` instance moves between states as files come and go, so
  /// one controller for the state's whole lifetime is what its own stream
  /// subscription already expects.
  AutosaveController? _autosave;

  @override
  void initState() {
    super.initState();
    // A ticker rather than `setState` from a timer: the viewport draws from
    // whatever the camera is now, and the frame is what asks for the next one.
    _ticker = createTicker(_onTick)..start();
    _timings.start();
    _autosave = AutosaveController(
      cubit: _cubit,
      storage:
          widget.autosaveStorage ?? defaultBinaryStorage('flutter3d_modeler'),
      sessionId: _kAutosaveSessionId,
      onIssue: (String said) => _cubit.say(said, important: true),
    );
    unawaited(_open());
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    installBeforeUnloadGuard(() => _history.isDirty);
    _liveCrashScreen = this;
  }

  void _onTick(Duration elapsed) {
    // Clamped because the first tick is measured from zero and a tab that was
    // in the background comes back with a gap of minutes: either one would
    // finish a quarter-second turn before its first frame was drawn.
    final double seconds = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(
      0.0,
      0.1,
    );
    _lastTick = elapsed;
    if (_state case ModelerReady(
      :final stage,
      :final mode,
      :final animationSubmode,
    )) {
      stage.orbit.advance(seconds);
      _surfaces.apply(stage.subject, _shading);
      // Reasserted every frame rather than only when a chip is pressed: the
      // lens and the shading are two of the three things a newly opened model
      // has to inherit, and a state that is reasserted cannot be got out of
      // step with the interface by anything.
      useLens(stage.camera, _lens, stage.orbit);
      // `S5`'s own row: idempotent and walked every frame the weights
      // sub-mode might be open, for `WeightGradientShading.apply`'s own
      // reason — a model opened while it is on brings nodes this has never
      // seen.
      _weightGradientShading.apply(
        stage.subject,
        active:
            mode == ModelerMode.animation &&
            animationSubmode == AnimationSubmode.weights,
      );
      _timelinePreview.tick(_history.project, stage.sync, seconds);
    }
    final said = _measurementRuns.step(
      elapsed.inMicroseconds,
      _lastRenderMicros,
    );
    if (said != null) _report = said;
    setState(() {});
  }

  @override
  void dispose() {
    if (identical(_liveCrashScreen, this)) _liveCrashScreen = null;
    _ticker?.dispose();
    _timings.stop();
    _autosave?.dispose();
    _lifecycle.dispose();
    _frame.dispose();
    if (kMcpPort >= 0) unawaited(stopMcpServer());
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FileDropZone(
    onDropped: (String name, Uint8List bytes) =>
        unawaited(_handleDroppedFile(name, bytes)),
    child: BlocBuilder<ModelerCubit, ModelerState>(
      bloc: _cubit,
      builder: (BuildContext context, ModelerState state) => _screen(state),
    ),
  );
}
