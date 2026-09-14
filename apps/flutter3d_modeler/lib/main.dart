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
import 'src/autosaving.dart';
import 'src/churn_run.dart';
import 'src/close_beforeunload.dart';
import 'src/close_guard.dart';
import 'src/crash_handling.dart';
import 'src/display_modes.dart';
import 'src/element_picker_cache.dart';
import 'src/element_picking.dart';
import 'src/environment_summary.dart';
import 'src/exporting.dart';
import 'src/files/fetch_model.dart';
import 'src/files/file_drop.dart';
import 'src/files/project_files.dart';
import 'src/files/sandbox_probe.dart';
import 'src/ground_grid.dart';
import 'src/import_plan.dart';
import 'src/material_editing.dart';
import 'src/material_pool.dart' show clay;
import 'src/mcp_bootstrap.dart';
import 'src/measurement_runs.dart';
import 'src/modeler_cubit.dart';
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
import 'src/staging.dart';
import 'src/timeline_preview_wiring.dart';
import 'src/tool_commands.dart';
import 'src/transform_dispatch.dart';
import 'src/transform_fields.dart';
import 'src/transform_session.dart';
import 'src/ui/export_screen.dart';
import 'src/ui/import_screen.dart';
import 'src/ui/lathe_dialog.dart';
import 'src/ui/layout_class.dart';
import 'src/ui/material_studio_dialog.dart';
import 'src/ui/measurement_report_overlay.dart';
import 'src/ui/modeler_keys.dart';
import 'src/ui/properties/properties_panel.dart';
import 'src/ui/save_as_dialog.dart';
import 'src/ui/shell.dart';
import 'src/ui/shell_phone.dart';
import 'src/ui/shell_tablet.dart';
import 'src/ui/shortcut_help_screen.dart';
import 'src/ui/start_screen.dart';
import 'src/ui/status_line.dart';
import 'src/ui/theme.dart';
import 'src/ui/tools.dart';
import 'src/ui/top_bar_actions.dart';
import 'src/viewport_metrics.dart';

/// The model this build opens, as an asset path. Empty means the cube.
///
/// A define rather than a file dialogue, because opening a file is `ui-14` and
/// this build exists before it: what a measurement needs is the same model on
/// every machine, named on the command line and shipped in the bundle.
const String kModel = String.fromEnvironment('model');

/// A lattice of this many triangles instead of a model, for the measurements.
///
///     flutter run -d macos --dart-define=stress=1000000 --dart-define=orbit=600
///
/// Zero — the default — leaves the subject alone.
const int kStress = int.fromEnvironment('stress');

/// How many draws that lattice is split across. One enormous mesh and a
/// thousand ordinary ones are different questions and a viewport meets both.
const int kStressObjects = int.fromEnvironment('objects', defaultValue: 1);

/// Turn the camera through a full circle over this many frames, print what the
/// frames cost, and stop. Zero leaves the camera to the pointer.
const int kOrbit = int.fromEnvironment('orbit');

/// Move one per cent of the subject's vertices every frame, rebuild the mesh
/// and upload it — the whole path an edit takes, timed stage by stage.
///
/// The measurement `p0-06` and `p0-11` ask for, and the one that says whether a
/// drag can be interactive at a given mesh size.
const bool kChurn = bool.fromEnvironment('churn');

/// Ask the platform what this process may write to, and show the answer.
///
/// `p0-13n`: the macOS sandbox grants a container and the file a person picks,
/// and nothing else. Which of those a save can actually use is a measurement,
/// not a guess — see `lib/src/files/sandbox_probe.dart`.
const bool kSandboxProbe = bool.fromEnvironment('sandbox');

/// With [kSandboxProbe], also open the save panel and write through it — the
/// half of `p0-13n` that no process can answer without a person.
const bool kSandboxPick = bool.fromEnvironment('sandboxPick');

/// `mcp-13n`: also serve this session's own live document over a local HTTP
/// socket, on this port — `0` picks any free one. Negative (the default)
/// starts nothing, the same "opt in by naming a value" `kStress` already
/// uses.
///
///     flutter run -d macos --dart-define=mcpPort=0
const int kMcpPort = int.fromEnvironment('mcpPort', defaultValue: -1);

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

/// Reaches whatever `ModelerScreen` is on screen right now — see
/// [_liveCrashScreen]'s own doc comment for why a top-level error handler
/// needs a door like this at all.
Future<void> _onUncaughtError(Object error, StackTrace stackTrace) =>
    handleCrash(
      error: error,
      stackTrace: stackTrace,
      cubit: _liveCrashScreen?._cubit,
      storage: _liveCrashScreen?._autosave?.storage,
      sessionId: _kAutosaveSessionId,
      environment: 'Flutter, ${environmentSummary()}',
      dialogContext: () => _rootNavigatorKey.currentContext,
    );

/// Where the dialog [_onUncaughtError] shows actually opens — a
/// `Navigator` above every route this application ever pushes, rather than
/// `ModelerScreen`'s own `BuildContext`: the crash that needs showing might
/// be the one that unmounted a dialog already open on top of it.
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Set for as long as one `_ModelerScreenState` is alive, cleared on
/// `dispose` — [_onUncaughtError] is a top-level function with no `State` of
/// its own, and this is how it reaches the one document this single-window
/// application ever has open, the same single-instance reasoning
/// `_kAutosaveSessionId`'s own doc comment already relies on.
_ModelerScreenState? _liveCrashScreen;

class ModelerApp extends StatelessWidget {
  const ModelerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _rootNavigatorKey,
    title: 'flutter3d modeller',
    debugShowCheckedModeBanner: false,
    theme: modelerTheme(),
    // `ui-22`: Russian and English both from the first version. What
    // `_cubit.say(...)` shows stays English on purpose — that is the
    // diagnostic language this repository already uses in core and MCP,
    // not the interface language.
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const ModelerScreen(),
  );
}

/// What the screen is doing. Three states, and no more until there is a
/// document to have states about.
class ModelerScreen extends StatefulWidget {
  const ModelerScreen({super.key, this.autosaveStorage});

  /// Where `ui-18`'s own autosave writes — null in every real build, which
  /// falls back to the platform's own `defaultBinaryStorage`. A test hands
  /// in a fake here instead of standing up a real filesystem or IndexedDB.
  final BinaryStorage? autosaveStorage;

  @override
  State<ModelerScreen> createState() => _ModelerScreenState();
}

/// `ui-18`'s own autosave key, for the one document this single-window app
/// ever has open at a time.
///
/// **A fixed string, not one minted per launch.** `recoveryPathFor`'s own
/// doc comment warns two different new documents must not collide on the
/// session id the way two openings of one saved file are meant to — but
/// that is a worry for an app that can hold several unsaved documents at
/// once, and this one cannot: there is exactly one `ModelerScreen`, so
/// exactly one autosave slot is exactly what a crash-recovery key needs. A
/// fresh id every launch would instead lose the previous session's own
/// autosave the moment the app that wrote it closed — the one case
/// autosave exists for.
const String _kAutosaveSessionId = 'single-window';

/// Whatever `sessionId`'s own autosave slot in `storage` holds, decoded —
/// null when there is nothing there, or when what is there does not read
/// back as a project at all.
///
/// **Pure IO and decode, no `BuildContext`, no dialog** — the part of
/// `ui-18`'s own "предложение восстановить" that a test can drive with
/// `FakeBinaryStorage` directly, the same split `autosave.dart`'s own
/// `shouldSave`/`decideRecovery` already make between deciding and doing.
/// A stale entry (one `readProject` refuses) is removed here rather than
/// left for the caller to notice twice — there is nothing for a person to
/// decide about a recovery copy this build itself could not have written.
Future<ProjectOpened?> findRecovery(
  BinaryStorage storage,
  String sessionId,
) async {
  final key = recoveryPathFor(null, sessionId: sessionId);
  final bytes = await storage.read(key);
  if (bytes == null) return null;
  final read = readProject(bytes);
  if (read is ProjectOpened) return read;
  await storage.remove(key);
  return null;
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
  /// `timeline_preview_wiring.dart`.
  final TimelinePreviewWiring _timelinePreview = TimelinePreviewWiring();

  /// [AnimationPanel.onSelectClip].
  void _selectAnimationClip(int? index) {
    if (_state case ModelerReady(:final project, :final stage)) {
      _timelinePreview.selectClip(project, stage.sync, index);
    }
  }

  /// [AnimationPanel.onTimeChanged].
  void _scrubAnimation(double time) => _timelinePreview.scrub(time);

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

  /// Answers the OS's own "can you close now?" — `ui-24`'s "при isDirty —
  /// диалог" on the platforms that ask this way rather than through a
  /// `Navigator` pop.
  Future<ui.AppExitResponse> _onExitRequested() async {
    if (!needsConfirmation(isDirty: _history.isDirty)) {
      return ui.AppExitResponse.exit;
    }
    final UnsavedChoice? choice = await _askUnsavedChoice();
    if (choice == null) return ui.AppExitResponse.cancel;
    final closed = await shouldClose(choice, write: _saveFile);
    return closed ? ui.AppExitResponse.exit : ui.AppExitResponse.cancel;
  }

  /// `PopScope`'s own callback when [canPop] blocked a pop — the in-app-nav
  /// half of `ui-24`'s dialog, for whatever platform routes an exit attempt
  /// through a `Navigator` pop rather than asking the OS directly.
  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (didPop) return;
    final UnsavedChoice? choice = await _askUnsavedChoice();
    if (choice == null) return;
    final closed = await shouldClose(choice, write: _saveFile);
    if (closed && mounted) await SystemNavigator.pop();
  }

  /// The three answers `close_guard.dart`'s own [UnsavedChoice] names, put
  /// in front of a person once — every caller that finds the document
  /// dirty on the way out asks through this one dialog rather than each
  /// growing a slightly different one.
  Future<UnsavedChoice?> _askUnsavedChoice() => showDialog<UnsavedChoice>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text('Unsaved changes'),
      content: const Text('This model has changes that have not been saved.'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(UnsavedChoice.keepEditing),
          child: const Text('Keep editing'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(UnsavedChoice.discard),
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(UnsavedChoice.save),
          child: const Text('Save and close'),
        ),
      ],
    ),
  );

  void _onTick(Duration elapsed) {
    // Clamped because the first tick is measured from zero and a tab that was
    // in the background comes back with a gap of minutes: either one would
    // finish a quarter-second turn before its first frame was drawn.
    final double seconds = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(
      0.0,
      0.1,
    );
    _lastTick = elapsed;
    if (_state case ModelerReady(:final stage)) {
      stage.orbit.advance(seconds);
      _surfaces.apply(stage.subject, _shading);
      // Reasserted every frame rather than only when a chip is pressed: the
      // lens and the shading are two of the three things a newly opened model
      // has to inherit, and a state that is reasserted cannot be got out of
      // step with the interface by anything.
      useLens(stage.camera, _lens, stage.orbit);
      _timelinePreview.tick(seconds);
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
    if (kMcpPort >= 0) unawaited(stopMcpServer());
    _cubit.close();
    super.dispose();
  }

  /// Swaps in a device sized for [width]/[height]/[devicePixelRatio] when the
  /// current one no longer fits — a viewport grown past a fixed-resolution
  /// canvas, or a display moved to a different pixel ratio. See
  /// `deviceStaleForViewport` and `ModelerCubit.redeviced` (`ui-20`).
  Future<void> _reopenDeviceIfStale(
    int width,
    int height,
    double devicePixelRatio,
  ) async {
    if (_reopeningDevice) return;
    if (!kFixedResolution) return;
    final now = _state;
    if (now is! ModelerReady) return;
    if (!deviceStaleForViewport(
      lastWidth: _deviceWidth,
      lastHeight: _deviceHeight,
      lastDevicePixelRatio: _deviceDevicePixelRatio,
      width: width,
      height: height,
      devicePixelRatio: devicePixelRatio,
    )) {
      return;
    }
    _reopeningDevice = true;
    try {
      final newDevice = await openDevice(width: width, height: height);
      if (!mounted) {
        return;
      }
      final opened = await openProject(now.history.project, device: newDevice);
      if (!mounted) {
        return;
      }
      _device = newDevice;
      _deviceWidth = width;
      _deviceHeight = height;
      _deviceDevicePixelRatio = devicePixelRatio;
      _cubit.redeviced(
        renderer: Renderer.create(device: newDevice),
        stage: opened.stage,
      );
    } finally {
      _reopeningDevice = false;
    }
  }

  Future<void> _open() async {
    // What it costs to get to the first frame, which on the web is a different
    // number from what a frame costs afterwards — and the one a person waiting
    // at a white page is actually measuring.
    final opening = Stopwatch()..start();
    // The document a new session starts with: one cube, so the first thing on
    // screen is a thing rather than an empty grid.
    final opening3 = ModelHistory(_newProject());
    try {
      // The size a web build's canvas is created at: `kFixedResolution` is
      // true there, so this is the resolution the browser scales from —
      // the screen's own logical size, so a canvas fits it from the first
      // frame rather than starting at a guess and reopening immediately
      // (`ui-20`). Impeller ignores it and sizes itself per frame.
      final view = ui.PlatformDispatcher.instance.views.firstOrNull;
      final devicePixelRatio = view?.devicePixelRatio ?? 1.0;
      final width = view == null
          ? 1600
          : (view.physicalSize.width / devicePixelRatio)
                .round()
                .clamp(1, 8192)
                .toInt();
      final height = view == null
          ? 1000
          : (view.physicalSize.height / devicePixelRatio)
                .round()
                .clamp(1, 8192)
                .toInt();
      final device = await openDevice(width: width, height: height);
      if (!mounted) return;
      _device = device;
      _deviceWidth = width;
      _deviceHeight = height;
      _deviceDevicePixelRatio = devicePixelRatio;
      final renderer = Renderer.create(device: device);

      final asset = kModel.isEmpty ? null : await _load(kModel, device);
      if (!mounted) return;

      // The measurement stands keep the old door: `p0-01` is about triangles on
      // a screen and putting a project behind a million-triangle lattice would
      // be measuring the document instead. Everything else comes through the
      // project, which is the one a person edits.
      final stage = kStress > 0 || asset != null
          ? ModelerStage.build(
              device: device,
              asset: asset,
              stressTriangles: kStress,
              stressObjects: kStressObjects,
            )
          : ModelerStage.fromProject(device: device, project: opening3.project);
      // Framed once, after the meshes are in: an object of any size arrives on
      // screen at a usable distance rather than as a dot or as the inside of
      // itself.
      stage.frameSubject();
      if (kChurn) {
        final subject = stage.subject;
        final node = subject is MeshNode
            ? subject
            : subject.children.whereType<MeshNode>().firstOrNull;
        final source = node?.mesh.source;
        if (node != null && source != null) {
          _measurementRuns.churn = ChurnRun(
            device: device,
            node: node,
            from: source,
          );
        }
      }
      opening.stop();
      _measurementRuns.openedInMs = opening.elapsedMilliseconds;
      if (kOrbit > 0) {
        _measurementRuns.orbit = OrbitRun(frames: kOrbit, stage: stage);
      }
      if (kSandboxProbe) {
        final said = describeProbe(await probeSandbox());
        debugPrint(said);
        if (mounted) _cubit.say(said);
        // The other half of the question needs the panel, and the panel needs
        // somebody to answer it: this opens it, and what comes back — the write
        // and whether a rename beside it would have worked — is printed the
        // same way. See `saveAs`.
        if (kSandboxPick) await _saveFile();
      }
      _cubit.opened(
        opening3,
        renderer: renderer,
        stage: stage,
        documentName: kModel.isEmpty ? 'cube' : kModel,
      );
      if (kMcpPort >= 0) {
        unawaited(startMcpServer(history: opening3, port: kMcpPort));
      }
      setState(() {
        // With no run to wait for, the opening cost is the whole report.
        if (kOrbit <= 0) {
          _report = 'opened in ${_measurementRuns.openedInMs} ms';
        }
      });
      // Opened from a link: the models service loads this build in a frame
      // with the file's address in the query, so the document becomes that
      // model rather than staying a cube.
      final linked = Uri.base.queryParameters['model'];
      if (linked != null && linked.isNotEmpty) {
        unawaited(
          _openLinked(
            Uri.base.resolve(linked),
            Uri.base.queryParameters['name'] ?? 'model',
            device,
          ),
        );
      } else if (kModel.isEmpty && kOrbit <= 0 && !kSandboxProbe) {
        // `ui-18`'s own "предложение восстановить" — checked once, on an
        // ordinary interactive launch only. A `--dart-define` measurement
        // run (`kModel`, `kOrbit`, `kSandboxProbe`) has nobody to answer a
        // dialog, and a link-open is about to replace the document anyway.
        unawaited(_offerRecovery(device));
      }
    } catch (error) {
      if (!mounted) return;
      _cubit.failed('$error');
    }
  }

  /// `ui-18`'s own "предложение восстановить": an autosave from a session
  /// that never closed cleanly, offered once, right after the ordinary open
  /// already put a cube on screen — never in place of it, since a recovery
  /// copy that itself fails to read (it should not, `_autosave` is the only
  /// thing that ever wrote this key) is not a reason to keep someone looking
  /// at a blank screen.
  Future<void> _offerRecovery(GraphicsDevice device) async {
    final storage = _autosave?.storage;
    if (storage == null) return;
    final read = await findRecovery(storage, _kAutosaveSessionId);
    if (read == null || !mounted) return;

    final restore = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Restore unsaved changes?'),
        content: Text(
          'An autosave from a session that did not close cleanly was found '
          '(${countLabel(read.project.objects.length, 'object')}).',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (restore != true) {
      await storage.remove(
        recoveryPathFor(null, sessionId: _kAutosaveSessionId),
      );
      return;
    }
    final stage = ModelerStage.fromProject(
      device: device,
      project: read.project,
    );
    stage.frameSubject();
    _cubit.opened(
      ModelHistory(read.project),
      renderer: (_state as ModelerReady).renderer,
      stage: stage,
      documentName: 'recovered',
      said: 'restored an autosave from a session that did not close cleanly',
    );
    setState(() {
      _elementPickerCache.forget();
    });
  }

  /// Opens a model the person chose, and puts it in the document.
  ///
  /// The whole of `p0-08` on the web and the ordinary path everywhere else:
  /// bytes from a picker, `decodeModel` over them, upload, frame. Nothing here
  /// branches on the platform — `ProjectFiles` already did.
  ///
  /// **The document is what is opened, and the picture follows from it.** This
  /// used to instantiate the decoded model straight into a scene and then start
  /// a fresh project holding a cube, which put the model on the screen and left
  /// every other half of the application describing something else: the
  /// outliner listed one cube, a click selected nothing that was drawn, undo had
  /// no edits to take back and `ExportReadiness` measured a shape nobody could
  /// see. `fromModelDocument` turns the file into objects, and `SceneSync`
  /// draws those — so what is picked, moved, undone and exported is the model
  /// that was opened.
  ///
  /// **The materials do not survive an import yet, and that is a known cost.**
  /// `mat-01` gives a project its material table, so a model imported from a
  /// glTF arrives painted; a project saved by this application carries its own
  /// and opens exactly as it was left.
  Future<void> _openFile() async {
    final device = _device;
    if (device == null) return;
    _cubit.say('choosing…');
    try {
      final picked = await openModel();
      if (picked == null) {
        if (mounted) _cubit.say('nothing chosen');
        return;
      }
      await _openBytes(picked.name, picked.bytes, device);
    } catch (error) {
      if (mounted) _cubit.say('could not open it: $error');
    }
  }

  /// Opens the model at [url], which the page this build was loaded into
  /// named.
  ///
  /// **Only an address on the origin this build was served from.** The query
  /// is something anybody can write into a link, and a frame that fetched
  /// whatever it was told would be a frame that sends this origin's cookies'
  /// worth of trust to another site's file.
  Future<void> _openLinked(Uri url, String name, GraphicsDevice device) async {
    if (url.origin != Uri.base.origin) {
      _cubit.say('not opening $name: it is not on ${Uri.base.origin}');
      return;
    }
    _cubit.say('fetching $name…');
    try {
      final fetched = await fetchModel(url, name: name);
      await _openBytes(fetched.name, fetched.bytes, device);
    } catch (error) {
      if (mounted) _cubit.say('could not open $name: $error');
    }
  }

  /// `ui-16`'s own import screen, threaded between a decoded [ModelDocument]
  /// and the [ImportOptions] `fromModelDocument` reads — a saved project
  /// skips straight past this, since it is not a model to be asked about.
  ///
  /// **Refused before decoding is a refusal, not a screen.** `ui-16`'s own
  /// worked example: a file over the web size limit never reaches
  /// [decodeBytes] at all, the same "cost nothing rather than something
  /// wrong" this file already keeps for a file that will not read.
  ///
  /// **Cancelling the screen is not an error.** [OpenRefused] is reused for
  /// it anyway, the same neutral tone `_openFile`'s own "nothing chosen"
  /// already reads in — the document on screen is untouched either way.
  Future<FileOpened> _openBytesWithImportScreen(
    String name,
    Uint8List bytes,
    GraphicsDevice device,
  ) async {
    if (isProjectFile(bytes)) {
      return openBytes(bytes, name: name, device: device);
    }

    final limitRefusal = refuseBeforeDecoding(
      fileSizeBytes: bytes.length,
      onWeb: kIsWeb,
    );
    if (limitRefusal != null) return OpenRefused(limitRefusal);

    final ModelDocument document;
    try {
      document = await decodeBytes(bytes, name);
    } catch (error) {
      return OpenRefused('$name could not be read: $error');
    }
    final empty = emptyDecodeRefusal(document, name);
    if (empty != null) return OpenRefused(empty);

    if (!mounted) return OpenRefused('import cancelled');
    final choice = await showImportScreen(
      context,
      document: document,
      profile: _history.project.profile,
    );
    if (choice == null) return OpenRefused('import cancelled');

    return openDocument(
      document,
      device: device,
      options: ImportOptions(scale: choice.unit.scale, upAxis: choice.upAxis),
    ).then(
      (OpenedModel opened) => OpenedModel(
        _applyImportCleanup(opened.project, choice),
        opened.stage,
      ),
    );
  }

  /// [project], with every `ImportedGeometry` object turned into real
  /// `EditMesh` topology via `importMeshData` when [choice] asks for any of
  /// weld/normals/triangulate — `BakeToMesh`'s own doc comment names this as
  /// where that conversion belongs. An object left untouched stays
  /// `ImportedGeometry`, byte for byte, which is this project's own default.
  ModelProject _applyImportCleanup(ModelProject project, ImportChoice choice) {
    if (!choice.weld && !choice.fixNormals && !choice.triangulate) {
      return project;
    }
    var result = project;
    for (final object in project.objects) {
      if (object.geometry case ImportedGeometry(:final data)) {
        final (mesh, _, _) = importMeshData(
          data,
          weldEpsilon: weldEpsilonFor(weld: choice.weld),
        );
        if (choice.fixNormals) mesh.makeConsistent();
        if (choice.triangulate) {
          triangulateFaces(mesh, Selection.all(mesh, ElementLevel.face));
        }
        result = result.withObject(
          object.copyWith(geometry: EditedGeometry(mesh)),
        );
      }
    }
    return result;
  }

  /// Puts the model in [bytes] in the document, whether it came from a picker
  /// or from a link.
  Future<void> _openBytes(
    String name,
    Uint8List bytes,
    GraphicsDevice device,
  ) async {
    try {
      final opening = Stopwatch()..start();
      final opened = await _openBytesWithImportScreen(name, bytes, device);
      opening.stop();
      if (!mounted) return;

      switch (opened) {
        // A file that will not read is a sentence on the status line and
        // nothing else: the document on screen is still the one the person was
        // working on, and throwing it away because they picked the wrong file
        // out of a folder would be the worst possible answer.
        case OpenRefused(:final String because):
          _cubit.say(because);
        case OpenedModel(
          :final ModelProject project,
          :final ModelerStage stage,
        ):
          stage.frameSubject();
          // The scene the old materials belonged to is going, and the
          // selection points at nodes that are no longer drawn.
          _surfaces.forget();
          final said = describeOpened(
            name: name,
            objectCount: project.objects.length,
            triangleCount: project.triangleCount,
            materialCount: project.materials.length,
            openedInMs: opening.elapsedMilliseconds,
          );
          _cubit.opened(
            ModelHistory(project),
            renderer: (_state as ModelerReady).renderer,
            stage: stage,
            documentName: name,
            said: <String>[said, ...opened.warnings].join('\n'),
          );
          setState(() {
            // Ids start again in the new project, so a picker held against the
            // old one could match a version and answer about a mesh that is
            // gone.
            _elementPickerCache.forget();
          });
      }
    } catch (error) {
      if (mounted) _cubit.say('could not open it: $error');
    }
  }

  /// Writes the document as the modeller's own file.
  ///
  /// **The project, not the picture.** This used to pull one `MeshData` off the
  /// scene's subject node and write it through `F3dWriter`, which meant a save
  /// that silently kept one mesh of however many the document held, threw away
  /// every name, transform and parent, and produced a file this application
  /// could not open back into the project it came from. `writeProject` writes
  /// the objects, their hierarchy, their material slots and the tables those
  /// index.
  ///
  /// `.f3d` is still a thing this can produce, and it is an *export* rather
  /// than a save — `ui-17`, and the difference is that an export is allowed to
  /// lose what the target format cannot hold, while a save is not.
  ///
  /// The spike part is what follows the write: `p0-13n` asks whether the same
  /// directory would have taken a temporary file and a rename, and the answer
  /// goes on the screen beside the result.
  /// `ui-33d`'s own "Save without history" checkbox is asked first, through
  /// [showSaveAsScreen] — a cancelled dialog is the same "nothing saved" a
  /// cancelled native panel already is, so it is reported the same way rather
  /// than treated as a silent no-op.
  /// Answers whether bytes actually landed on disk — `ui-24`'s own
  /// "неудачная запись не закрывает" needs to know, not just report.
  Future<bool> _saveFile() async {
    if (_state is! ModelerReady) return false;

    final choice = await showSaveAsScreen(context);
    if (choice == null) {
      if (mounted) _cubit.say('nothing saved', important: true);
      return false;
    }
    if (!mounted) return false;

    final Uint8List bytes;
    try {
      bytes = writeProject(
        _history.project,
        // `doc-31d`'s own `history` parameter: null is what leaves the
        // section out of the file entirely, the same way `ModelSession.save`
        // already does it in `flutter3d_model_mcp`.
        history: choice.includeHistory ? _history : null,
      );
    } on ArgumentError catch (error) {
      // What the format has no section for yet — a mesh carrying morph
      // targets. The message names the object, and it belongs in front of the
      // person rather than in a stack trace.
      _cubit.say('not saved: ${error.message}', important: true);
      return false;
    }
    final result = await saveAs(bytes, suggestedName: 'model.f3dproj');
    var said = switch (result.outcome) {
      SaveOutcome.written => 'wrote ${bytes.length} bytes to ${result.path}',
      SaveOutcome.cancelled => 'nothing saved',
      SaveOutcome.refused => result.said ?? 'refused',
    };
    final path = result.path;
    if (result.outcome == SaveOutcome.written && path != null) {
      final why = await whyAtomicWriteFails(path);
      said += why == null
          ? '\na temporary file and a rename would also have worked'
          : '\na temporary file and a rename would not: $why';
    }
    final written = result.outcome == SaveOutcome.written;
    // A cancelled picker or a refusal has not put the document in the state
    // a person who chose "save and close" asked to leave it in — only an
    // actual write clears dirty, the same way `ModelHistory.markSaved`'s
    // own doc comment already puts it.
    if (written) _history.markSaved();
    // Written or not, this is the direct outcome of a save a person just
    // asked for — worth reading, not something a stray selection click after
    // it should erase before they get the chance.
    if (mounted) _cubit.say(said, important: true);
    return written;
  }

  /// Takes the document out to a format somebody else reads.
  ///
  /// **An export may lose what the target cannot hold, and says what.** That is
  /// the whole difference from `_saveFile`: a `.f3dproj` keeps the parameters a
  /// cylinder knows itself by and the hierarchy, and an OBJ keeps triangles and
  /// a colour. So the person is told rather than protected — the errors stop
  /// the write until they answer, and the warnings ride along with it.
  Future<void> _exportFile(
    ExportFormat format, {
    bool bakeTransforms = false,
    TextureEncoding textureEncoding = TextureEncoding.png,
    // The export screen's own "Export anyway" label already showed every
    // issue this would otherwise ask about a second time — `ui-17`'s own
    // row, and the review's own finding that the two dialogs partly
    // duplicated each other. `_askAnyway` still exists for the top-bar's
    // own smaller entry points, which show no issue list of their own
    // first.
    bool skipConfirm = false,
  }) async {
    if (_state is! ModelerReady) return;

    var planned = planExport(
      _history.project,
      format: format,
      bakeTransforms: bakeTransforms,
      textureEncoding: textureEncoding,
      force: skipConfirm,
    );

    if (planned case final ExportBlocked blocked) {
      // Unreachable when skipConfirm is true: the first planExport call
      // above already passed force: skipConfirm, so a blocked plan only
      // ever reaches here when nobody has been asked yet.
      final go = await _askAnyway(blocked, blocked.issues);
      if (!go || !mounted) return;
      planned = planExport(
        _history.project,
        format: format,
        force: true,
        bakeTransforms: bakeTransforms,
        textureEncoding: textureEncoding,
      );
    }

    switch (planned) {
      case ExportRefused(:final String because):
        _cubit.say(because, important: true);
      case ExportBlocked():
        // Unreachable: the branch above either forced or returned. Named rather
        // than defaulted, so that adding a case to `ExportResult` is a compile
        // error here instead of a silent nothing.
        _cubit.say('not exported', important: true);
      case ExportWritten(
        :final List<ExportFile> files,
        :final List<String> warnings,
      ):
        final said = <String>[];
        for (final ExportFile file in files) {
          final result = await saveAs(file.bytes, suggestedName: file.name);
          said.add(switch (result.outcome) {
            SaveOutcome.written =>
              'wrote ${file.bytes.length} bytes to ${result.path}',
            SaveOutcome.cancelled => 'nothing saved',
            SaveOutcome.refused => result.said ?? 'refused',
          });
          // The `.mtl` is only worth asking for if the `.obj` was taken; a
          // person who cancelled the first panel has cancelled the export.
          if (result.outcome != SaveOutcome.written) break;
        }
        if (mounted) {
          _cubit.say(
            <String>[...said, ...warnings].join('\n'),
            important: true,
          );
        }
    }
  }

  /// `ui-17`'s own export screen — format, every readiness issue with a way
  /// to see what it is about, the triangle budget as a bar, and the "bake
  /// node transforms" flag. `ui-10`'s own row ("клик → диалог экспорта")
  /// wired the status line's readiness sentence and `⌘E` to a much smaller
  /// format-only dialog as a placeholder for this; both now open this
  /// screen instead, so there is one export entry point rather than two
  /// that could drift apart.
  Future<void> _showExportDialog() async {
    if (_state is! ModelerReady) return;
    final choice = await showExportScreen(
      context,
      project: _history.project,
      onShow: (int id) {
        _history.selection = _history.selection.copyWith(
          mode: SelectionMode.object,
          objects: <int>[id],
        );
        _cubit.documentMoved();
      },
    );
    if (choice != null) {
      unawaited(
        _exportFile(
          choice.format,
          bakeTransforms: choice.bakeTransforms,
          textureEncoding: choice.textureEncoding,
          skipConfirm: choice.acknowledgedWarnings,
        ),
      );
    }
  }

  /// `ui-13`'s own lathe dialog: `AddLathe` needs a profile, and this is the
  /// only place one gets drawn. Cancelling runs nothing at all — a person
  /// backing out of the dialog should not have to undo a box they never
  /// asked for.
  Future<void> _openLatheDialog() async {
    if (_state is! ModelerReady) return;
    final choice = await showLatheDialog(
      context,
      renderer: (_state as ModelerReady).renderer,
    );
    if (choice != null) {
      _cubit.ran(
        AddLathe(
          profile: choice.profile,
          segments: choice.segments,
          closedProfile: choice.closedProfile,
        ),
      );
    }
  }

  /// `mat-15`'s own studio: previews whatever material the active selection
  /// carries — or clay, when nothing is selected or the pool has not built
  /// one for it yet — on a body of its own, under a sky of its own. Nothing
  /// it does is undoable, because nothing it does changes the document: it
  /// hands back no result at all.
  Future<void> _openMaterialStudio() async {
    if (_state is! ModelerReady) return;
    final ready = _state as ModelerReady;
    final selectedId = ready.selection.activeObject;
    final selectedObject = selectedId == null
        ? null
        : ready.project[selectedId];
    final material = selectedObject == null
        ? null
        : ready.stage.materials?.forObject(selectedObject);
    await showMaterialStudioDialog(
      context,
      renderer: ready.renderer,
      material: material ?? clay(),
      selectedObjectMesh: selectedId == null
          ? null
          : ready.stage.sync?.nodeOf(selectedId)?.mesh,
    );
  }

  /// `ui-32n`'s own shortcut-help screen, opened by `?` or the Help button.
  void _showShortcutHelp() {
    if (_state is! ModelerReady) return;
    unawaited(showShortcutHelp(context));
  }

  /// `rel-15`'s own "Report a problem" button: opens a GitHub issue draft
  /// against `modeler_report.yml`, prefilled and sent nowhere on its own —
  /// [reportProblemUrl]'s own doc comment is the whole design here.
  /// [environmentSummary]'s own doc comment explains what "environment"
  /// actually holds and why.
  void _reportProblem() {
    unawaited(
      launchUrl(
        reportProblemUrl(environment: 'Flutter, ${environmentSummary()}'),
      ),
    );
  }

  /// `ui-15`'s own start screen: "Open file", "New project" with a profile,
  /// and the recent-models list `RecentModels` already keeps.
  Future<void> _showStartScreen() async {
    final device = _device;
    if (device == null || _state is! ModelerReady) return;
    final recent = RecentModels().read(exists: pathExists);
    if (!mounted) return;
    final choice = await showStartScreen(context, recentPaths: recent);
    if (!mounted || choice == null) return;
    switch (choice) {
      case OpenFileChoice():
        await _openFileAndRemember(device);
      case OpenRecentChoice(:final String path):
        await _openRecent(path, device);
      case NewProjectChoice(:final ProjectProfile profile):
        _newProjectWith(profile);
    }
  }

  /// "Open file" from the start screen — the same picker `_openFile` uses,
  /// with the chosen path written into `RecentModels` on success.
  ///
  /// **A sibling of `_openFile` rather than a change to it.** `_openFile`'s
  /// own body is mid-rewrite in a concurrent session's own uncommitted work
  /// (extracting the shared `_openBytes` this file already calls) — adding a
  /// line inside a function somebody else is simultaneously restructuring
  /// is not a safe edit to make no matter how small, so this repeats the
  /// picker call here instead of reaching into `_openFile`'s own body. The
  /// toolbar's own "Open" button keeps calling plain `_openFile` and does
  /// not record yet; folding the two into one recording path is a follow-up
  /// once that rewrite lands.
  Future<void> _openFileAndRemember(GraphicsDevice device) async {
    _cubit.say('choosing…');
    try {
      final picked = await openModel();
      if (picked == null) {
        if (mounted) _cubit.say('nothing chosen');
        return;
      }
      final opening = Stopwatch()..start();
      final opened = await openBytes(
        picked.bytes,
        name: picked.name,
        device: device,
      );
      opening.stop();
      if (!mounted) return;
      switch (opened) {
        case OpenRefused(:final String because):
          _cubit.say(because);
        case OpenedModel(
          :final ModelProject project,
          :final ModelerStage stage,
        ):
          stage.frameSubject();
          _surfaces.forget();
          final said = describeOpened(
            name: picked.name,
            objectCount: project.objects.length,
            triangleCount: project.triangleCount,
            materialCount: project.materials.length,
            openedInMs: opening.elapsedMilliseconds,
          );
          _cubit.opened(
            ModelHistory(project),
            renderer: (_state as ModelerReady).renderer,
            stage: stage,
            documentName: picked.name,
            said: <String>[said, ...opened.warnings].join('\n'),
          );
          setState(() {
            _elementPickerCache.forget();
          });
      }
      // A browser's own PickedFile has no path — nothing to remember there,
      // and RecentModels reads that the same way a first launch does.
      if (picked.path case final String path) {
        RecentModels().remember(path, exists: pathExists);
      }
    } catch (error) {
      if (mounted) _cubit.say('could not open it: $error');
    }
  }

  /// A row from the start screen's own recent list, tapped. The sandbox's
  /// grant for a path it did not just hand out itself does not outlive the
  /// run that earned it — `readRecentModel`'s own doc comment — so a null
  /// here is the ordinary case to expect on a later launch, not a bug.
  Future<void> _openRecent(String path, GraphicsDevice device) async {
    final bytes = await readRecentModel(path);
    if (!mounted) return;
    if (bytes == null) {
      _cubit.say('could not reopen $path; use Open file instead');
      return;
    }
    final opening = Stopwatch()..start();
    final name = path.split(RegExp(r'[\\/]')).lastOrNull ?? path;
    final opened = await openBytes(bytes, name: name, device: device);
    opening.stop();
    if (!mounted) return;
    switch (opened) {
      case OpenRefused(:final String because):
        _cubit.say(because);
      case OpenedModel(:final ModelProject project, :final ModelerStage stage):
        stage.frameSubject();
        _surfaces.forget();
        final said = describeOpened(
          name: name,
          objectCount: project.objects.length,
          triangleCount: project.triangleCount,
          materialCount: project.materials.length,
          openedInMs: opening.elapsedMilliseconds,
        );
        _cubit.opened(
          ModelHistory(project),
          renderer: (_state as ModelerReady).renderer,
          stage: stage,
          documentName: name,
          said: <String>[said, ...opened.warnings].join('\n'),
        );
        setState(() {
          _elementPickerCache.forget();
        });
    }
    RecentModels().remember(path, exists: pathExists);
  }

  /// "New project" from the start screen, with the profile picked there.
  void _newProjectWith(ProjectProfile profile) {
    final device = _device;
    if (device == null || _state is! ModelerReady) return;
    final project = _newProject().copyWith(profile: profile);
    final stage = ModelerStage.fromProject(device: device, project: project);
    stage.frameSubject();
    _surfaces.forget();
    _cubit.opened(
      ModelHistory(project),
      renderer: (_state as ModelerReady).renderer,
      stage: stage,
      documentName: 'untitled (${profile.name})',
    );
    setState(() {
      _elementPickerCache.forget();
    });
  }

  /// Asks whether to export a model that will not load cleanly.
  ///
  /// A dialog rather than a refusal, because the alternative is this
  /// application deciding what somebody's model is for. It names what will be
  /// wrong rather than counting it: "3 problems" is a number nobody can act on.
  Future<bool> _askAnyway(
    ExportBlocked blocked,
    List<ExportIssue> issues,
  ) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Export anyway?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(blocked.says),
            const SizedBox(height: 12),
            for (final ExportIssue issue in issues.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  issue.message,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            if (issues.length > 5)
              Text(
                'and ${issues.length - 5} more',
                style: const TextStyle(fontSize: 12.5),
              ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Export anyway'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  /// A click in the mesh mode: what element is under it, at the level the
  /// sub-mode names.
  void _pickedElement(
    PickingView view,
    Offset at,
    PointerDeviceKind pointer, {
    required bool extend,
  }) {
    final MeshPicker? picker = _elementPicker;
    if (picker == null) return;
    final picked = pickElementAt(
      picker,
      view,
      at: at,
      pointer: pointer,
      level: levelOf(_submode),
    );
    setState(() {
      final was = _history.selection;
      // Shift takes an element back out rather than only ever adding: dropping
      // one face from a selection of forty is otherwise thirty-nine clicks.
      final Selection next = extend && was.level == picked.level
          ? was.asMeshSelection.toggle(picked)
          : picked;
      _history.selection = was.copyWith(
        mode: SelectionMode.mesh,
        level: next.level,
        elements: next.ids.toList(),
      );
      _cubit.say(null);
    });
  }

  /// Presses a rail button.
  void _ranTool(String id) {
    if (kDragTools.contains(id) || id.endsWith('.select')) {
      // Arming rather than acting: these wait for a pointer.
      _cubit.tool(id);
      return;
    }
    if (id == 'object.lathe') {
      // A dialog, not a command run straight from the rail: `AddLathe`
      // needs a profile nobody has drawn yet, so this arms the button and
      // opens `lathe_dialog.dart` rather than going through `commandFor`,
      // which only ever answers with a command ready to run immediately.
      _cubit.tool(id);
      unawaited(_openLatheDialog());
      return;
    }
    final ModelCommand? command = commandFor(
      id,
      activeObject: _history.selection.activeObject,
      editMesh: _editMesh,
    );
    if (command == null) {
      _cubit.tool(id);
      return;
    }
    _cubit
      ..tool(id)
      ..ran(command);
  }

  /// A rectangle was dragged and let go.
  ///
  /// **The rules are `applyBox`'s and they are the same rules a click
  /// follows** — shift adds, control takes away, neither replaces — because a
  /// modifier that means one thing for a click and another for a box is a
  /// modifier nobody can rely on.
  void _boxed(SelectionBox box, PickingView view) {
    final was = _history.selection;
    if (was.mode == SelectionMode.mesh) {
      final MeshPicker? picker = _elementPicker;
      if (picker == null) return;
      final Selection caught = pickElementsIn(
        picker,
        view,
        rect: box.rect,
        level: levelOf(_submode),
      );
      final Set<int> next = applyBox<int>(
        was.elements.toSet(),
        caught.ids.toSet(),
        mode: box.mode,
      );
      setState(() {
        _history.selection = was.copyWith(
          elements: next.toList()..sort(),
          level: caught.level,
        );
        _cubit.say(null);
      });
      return;
    }

    // Objects, by the middle of what they cover rather than by every vertex in
    // them. **The middle and not an overlap**, which is what every modeller
    // does and is the more useful of the two: a box drawn across a crowded
    // scene to catch the three props in it should not also catch the floor
    // whose bounds run under all of them. Through the same frustum the element
    // picker uses, so the two answer the same question about one rectangle.
    final state = _state;
    if (state is! ModelerReady) return;
    final sync = state.stage.sync;
    if (sync == null) return;
    // A rectangle with no area — a drag that never left one axis — reaches
    // here as an ordinary release, not a mistake to refuse. `frustumOverBox`
    // answers it the same way `pickElementsIn` already does for the
    // mesh-mode branch above: nothing caught, rather than letting
    // `frustumOver`'s own divide-by-zero guard throw into the pointer
    // handler.
    final vm.Frustum? frustum = frustumOverBox(view, box.rect);
    final Set<int> caught = frustum == null
        ? const <int>{}
        : <int>{
            for (final ModelObject object in _history.project.objects)
              if (sync.nodeOf(object.id) case final MeshNode node)
                if (frustum.containsVector3(node.worldBounds.center)) object.id,
          };
    final Set<int> next = applyBox<int>(
      was.objects.toSet(),
      caught,
      mode: box.mode,
    );
    setState(() {
      _history.selection = was.copyWith(
        mode: SelectionMode.object,
        objects: next.toList(),
      );
      _cubit.say(null);
    });
  }

  /// Runs a selection command.
  ///
  /// **Through the history like everything else**, which is the point of
  /// `doc-32n`: a selection made by mistake is one press of ⌘Z away, the
  /// journal records what was selected when a command ran, and an agent
  /// driving the modeller can ask for it by name.
  void _runSelection(ModelCommand command) => _cubit.ran(command);

  /// Nine numbers typed into the panel.
  ///
  /// **What command this becomes is `transform_dispatch.dart`'s own
  /// question, not this file's.** A position or a rotation edit is read as a
  /// difference from what the panel showed a moment before and handed to
  /// `MoveBy`/`RotateBy`, which is what makes [_pivot] and [_space] mean
  /// anything for more than one object selected; a scale edit still sets the
  /// held object alone, for the reason that file's own doc argues. Either way
  /// the same number typed back is the same fields handed in twice, which
  /// `transformCommandFor` reads as nothing changed rather than a move by
  /// zero.
  void _setTransform(int id, TransformFields to) {
    final held = _history.project[id];
    if (held == null) return;
    final decided = transformCommandFor(
      heldId: id,
      from: transformFieldsOf(held.transform),
      to: to,
      pivot: transformPivotOf(_pivot),
      space: _space,
    );
    if (decided.refused case final String said) {
      _cubit.say(said);
      return;
    }
    if (decided.command case final ModelCommand command) {
      _cubit.ran(command);
    }
  }

  /// The material list's own tap: paint the held object with a different
  /// row, or — the row already active — take its paint off.
  void _assignMaterial(int id, int? to) =>
      _cubit.ran(AssignMaterial(id: id, to: to));

  void _addMaterial() => _cubit.ran(const AddMaterial());

  /// `anim-07`'s own two commands: a diamond finished a drag in
  /// `TimelinePanel`, or "Add" was pressed under `ActionsList`.
  void _moveKeys(MoveKeys command) => _cubit.ran(command);

  void _addClip() => _cubit.ran(const AddClip());

  void _setMaterialField(int index, String field, Object? value) =>
      _cubit.ran(SetMaterialField(index: index, field: field, value: value));

  void _setModifierField(int id, int index, String field, Object? value) =>
      _cubit.ran(
        SetModifierField(id: id, index: index, field: field, value: value),
      );

  void _clearTexture(int index, String slot) =>
      _cubit.ran(SetTexture(materialIndex: index, slot: slot));

  /// Opens a picker for an image and points one of a material's five texture
  /// slots at it — `mat-04`'s own row generalises `mat-04a-n`'s base colour
  /// slot alone over every name [SetTexture.slot] takes.
  ///
  /// **Two commands, two steps of history.** [AddImage] interns the bytes —
  /// or reuses the row a duplicate already sits in — and [SetTexture] is the
  /// only command that can then name the slot; there is no single command
  /// that does both, so a texture pick is honestly two edits rather than one
  /// pretending to be one.
  Future<void> _chooseTexture(int materialIndex, String slot) async {
    final PickedFile? file = await openImage();
    if (file == null) return;
    if (!_cubit.ran(AddImage(bytes: file.bytes, imageName: file.name))) {
      return;
    }
    final int? index = indexOfImageBytes(_history.project.images, file.bytes);
    if (index == null) return;
    _cubit.ran(
      SetTexture(materialIndex: materialIndex, slot: slot, imageIndex: index),
    );
  }

  /// The operation card's number was dragged.
  void _amend(ModelCommand to) {
    final said = _history.amend(to);
    if (said != null) {
      _cubit.say(said);
      return;
    }
    _cubit.documentMoved(said: to.says);
  }

  /// ⌘Z and ⇧⌘Z.
  void _undo() => _cubit.undo();

  void _redo() => _cubit.redo();

  /// What a click in the viewport did to the selection.
  ///
  /// The rules are all in `applyPick`, which is where they can be read and
  /// tested without a window; this is the seam that gives it the two things it
  /// cannot know — what is selected now, and whether shift was down.
  void _picked(PickResult pick, {required bool extend}) {
    final state = _state;
    if (state is! ModelerReady) return;
    final sync = state.stage.sync;
    if (sync == null) return;

    // The renderer answers with the leaf it rasterised; the document speaks in
    // ids. `SceneSync` is the only place that knows which is which, and a
    // second map here would be a second thing to keep in step.
    final int? id = switch (pick) {
      PickedObject(:final node) => sync.objectOf(node),
      // The viewport's own furniture. Not "nothing": clicking a gizmo's arrow
      // is the first half of a drag of the very object that is selected, and
      // clearing there would delete the selection out from under it.
      PickedService() => null,
      PickedNothing() => null,
    };
    final was = _history.selection;
    final List<int>? next = nextSelection(
      id: id,
      isService: pick is PickedService,
      current: was.objects,
      extend: extend,
    );
    if (next == null) return;
    setState(() {
      _history.selection = was.copyWith(
        mode: SelectionMode.object,
        objects: next,
      );
      _cubit.say(null);
    });
  }

  /// What the selection is, in the words the status line shows.
  String get _selectionSaid => _history.selection.says;

  /// Reads a model out of the bundle and uploads it.
  ///
  /// Through the isolate loader, which is what an application does: decoding
  /// the Khronos helmet costs a third of a frame at best, and a viewport that
  /// stutters while opening is the first thing anybody notices.
  static Future<ModelAsset> _load(String path, GraphicsDevice device) async {
    final document = await decodeModelInIsolate(
      ModelLoadRequest(source: BundleAssetSource(path)),
    );
    return ModelAsset.fromDocument(document, device: device, name: path);
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

  /// A file dragged onto the window — `ui-31n`'s own door onto the same path
  /// `_openFile` already opens by hand.
  ///
  /// **Wrapped once, around the whole shell, rather than around the
  /// viewport.** A person drops a file wherever the pointer happens to be —
  /// over the outliner, the properties panel, the rail — and only one of
  /// those is the viewport; a window is either a place a file can land or it
  /// is not, and `ui-14`/`ui-16`'s own picker was never restricted to one
  /// widget either.
  ///
  /// **`unopenableDropRefusal` runs before any of the rest of this, and that
  /// is the one thing dropping cannot skip.** `openModel`'s own dialogue only
  /// ever offers this build's own extensions, so `_openFile` never has to ask
  /// — a drop can carry anything the desktop or the browser lets somebody
  /// drag onto the window, including a file this build has no reader for at
  /// all, and the answer for that is a sentence rather than a guess at what
  /// the bytes might be.
  Future<void> _handleDroppedFile(String name, Uint8List bytes) async {
    final device = _device;
    if (device == null || _state is! ModelerReady) return;
    if (unopenableDropRefusal(name, bytes) case final String because) {
      _cubit.say(because);
      return;
    }
    await _openBytesWithImportScreen(name, bytes, device);
  }

  Widget _screen(ModelerState state) => switch (state) {
    ModelerOpening() => const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    ),
    // `ui-15` is the start screen and this is the state it will show in. Until
    // it exists there is no way to reach this, and a wildcard here would be a
    // silent blank window on the day somebody adds the first path to it.
    ModelerChoosing(:final said) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(said, textAlign: TextAlign.center),
        ),
      ),
    ),
    ModelerFailed(:final said) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(said, textAlign: TextAlign.center),
        ),
      ),
    ),
    ModelerReady(:final renderer, :final stage) => Title(
      title: windowTitleFor(isDirty: state.history.isDirty),
      color: Colors.black,
      // `ui-24`'s own "при isDirty — диалог" on the platforms that route an
      // exit attempt through a `Navigator` pop — Android's back gesture,
      // chiefly, since this single-screen app has nothing else to pop to.
      // `_onExitRequested` covers the desktop window-close case, which
      // never goes through here at all.
      child: PopScope(
        canPop: !state.history.isDirty,
        onPopInvokedWithResult: _onPopInvoked,
        child: ModelerKeys(
          onKey: _transformSession.modalKey,
          onUndo: _undo,
          onRedo: _redo,
          onExport: _showExportDialog,
          onTool: _ranTool,
          onSelectAll: () => _runSelection(const SelectAll()),
          onSelectNone: () => _runSelection(const SelectNone()),
          onInvertSelection: () => _runSelection(const InvertSelection()),
          onShortcutHelp: _showShortcutHelp,
          onLevel: _cubit.submode,
          tools: toolsFor(state.mode),
          // **`ui-05`'s own three shells, built once and picked by width.** The
          // actions/status/properties/viewport widgets below are the same
          // objects whichever shell draws them — `ui-05`'s own acceptance is
          // that the same tools answer to the same keys in all three, and
          // building them once here rather than once per shell branch is what
          // makes that true by construction rather than by three call sites
          // staying in sync by hand.
          child: Builder(
            builder: (BuildContext context) {
              final actions = <Widget>[
                TopBarActions(
                  canUndo: state.history.canUndo,
                  canRedo: state.history.canRedo,
                  undoSays: state.history.undoSays,
                  redoSays: state.history.redoSays,
                  onUndo: _undo,
                  onRedo: _redo,
                  onAddPrimitive: (String kind) =>
                      _cubit.ran(AddPrimitive(kind: kind)),
                  onOpen: _openFile,
                  onSave: _saveFile,
                  onExport: _exportFile,
                  onMaterialStudio: () => unawaited(_openMaterialStudio()),
                  onShortcutHelp: _showShortcutHelp,
                  onStartScreen: () => unawaited(_showStartScreen()),
                  onReportProblem: _reportProblem,
                ),
              ];
              final status = StatusLine(
                // One sentence, carried by the state. There used to be two — one for
                // files and one for operations — with the operation's winning by
                // sitting first in a `??` chain, which meant a file that failed to
                // open said nothing at all if an operation had run before it.
                said: state.said ?? _selectionSaid,
                // A value on the state, refreshed when a command lands rather than
                // computed while a frame is drawn. It cannot go stale behind a check
                // that never runs, which is what a getter here could do.
                readiness: state.readiness,
                triangles: state.project.triangleCount,
                micros: _lastRenderMicros,
                onExport: _showExportDialog,
              );
              final properties = PropertiesPanel(
                mode: state.mode,
                stage: stage,
                project: state.project,
                selection: state.selection,
                onSelect: (int id) {
                  // Straight onto the history's selection rather than through a
                  // command: `doc-32n` gave the *set* operations commands — all,
                  // none, invert, grow — and picking one object out of the outliner
                  // is not one of them yet. When it is, this becomes `_cubit.ran`.
                  state.history.selection = state.selection.copyWith(
                    mode: SelectionMode.object,
                    objects: <int>[id],
                  );
                  _cubit.documentMoved();
                },
                onTransform: _setTransform,
                pivot: _pivot,
                onPivot: (PivotChip to) => setState(() => _pivot = to),
                space: _space,
                onSpace: (TransformSpace to) => setState(() => _space = to),
                onRename: (int id, String to) =>
                    _cubit.ran(Rename(id: id, to: to)),
                onToggleModifier: (int id, int index) =>
                    _cubit.ran(ToggleModifier(id: id, index: index)),
                onReorderModifier: (int id, int from, int to) =>
                    _cubit.ran(ReorderModifier(id: id, from: from, to: to)),
                // Phase one's own stack has exactly one buildable kind — the
                // mirror `mesh-41` already gives it. `ui-08`'s own "Add" link
                // reaches for it directly rather than opening a picker with one
                // entry in it.
                onAddModifier: (int id) => _cubit.ran(
                  AddModifier(
                    id: id,
                    modifier: MirrorModifier(normal: vm.Vector3(1, 0, 0)),
                  ),
                ),
                onSetModifierField: _setModifierField,
                onAssignMaterial: _assignMaterial,
                onAddMaterial: _addMaterial,
                onSetMaterialField: _setMaterialField,
                onChooseTexture: _chooseTexture,
                onClearTexture: _clearTexture,
                onMoveKeys: _moveKeys,
                onAddClip: _addClip,
                onSelectAnimationClip: _selectAnimationClip,
                onScrubAnimation: _scrubAnimation,
                lastCommand: state.history.journal.isEmpty
                    ? null
                    : state.history.journal.last,
                onAmend: _amend,
                shading: _shading,
                onShading: (ShadingMode mode) =>
                    setState(() => _shading = mode),
                lens: _lens,
                onLens: (ViewLens lens) => setState(() => _lens = lens),
                onView: (StandardView view) => lookFrom(stage.orbit, view),
              );
              final viewport = Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: ModelerViewport(
                      renderer: renderer,
                      stage: stage,
                      onFrame: () {},
                      onRendered: (int micros) => _lastRenderMicros = micros,
                      onViewportMetrics: (int width, int height, double dpr) =>
                          unawaited(_reopenDeviceIfStale(width, height, dpr)),
                      // One or the other, never both: a click in the mesh mode is a
                      // question about this mesh's elements and is answered on the
                      // CPU, and asking the renderer for a node as well would cost a
                      // whole frame to answer a question nobody asked.
                      onPick: _mode == ModelerMode.mesh ? null : _picked,
                      onElementPick:
                          _mode == ModelerMode.mesh && _editMesh != null
                          ? _pickedElement
                          : null,
                      // One or the other: with a transform tool armed a left drag is
                      // the transform, and with none it is a rectangle. A viewport
                      // that offered both would have to guess, and the guess would be
                      // wrong on the frame a person changed their mind.
                      onDragTool: kDragTools.contains(_tool)
                          ? _transformSession.dragged
                          : null,
                      onDragDone: _transformSession.endDrag,
                      onBox: _boxed,
                      // The gizmo stands on the selection and offers the transform
                      // the armed tool asks for. On a tablet it is the only way in:
                      // there is no `G` key on an iPad, so this is not a second path
                      // to the same place — on three of the five platforms phase 1
                      // ships to it is the path.
                      gizmoPivot: _transformSession.gizmoPivot,
                      gizmoKind: _transformSession.gizmoKind,
                      onGizmoDrag: _transformSession.grabbedGizmo,
                      snapHighlight: _transformSession.snapTarget?.position,
                      editMesh: _mode == ModelerMode.mesh ? _editMesh : null,
                      elements: _history.selection.asMeshSelection,
                      meshVersion:
                          _history
                              .project[_history.selection.activeObject ?? -1]
                              ?.version ??
                          0,
                      elementsVersion: _history.selection.elements.length,
                      settings: settingsFor(
                        _shading,
                        // The outline is the renderer's until the overlay draws the
                        // selection itself and can say which *part* of an object is
                        // selected. Until then this is what tells a person their click
                        // landed.
                        RenderSettings(
                          highlighted: <SceneNode>[
                            for (final int id in _history.selection.objects)
                              if (stage.sync?.nodeOf(id) case final SceneNode n)
                                n,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: OrientationDial(
                      yaw: stage.orbit.yaw,
                      pitch: stage.orbit.pitch,
                      onPressed: (ViewAxis axis) {
                        // The dial says where; the controller does the turning, and
                        // takes the short way round because `viewAlong` already chose
                        // the turn nearest the yaw the camera is at.
                        final view = const OrientationGizmo().viewAlong(
                          axis,
                          fromYaw: stage.orbit.yaw,
                        );
                        stage.orbit.animateTo(yaw: view.yaw, pitch: view.pitch);
                      },
                    ),
                  ),
                  if (_report case final String said)
                    MeasurementReportOverlay(said: said),
                ],
              );

              void onMode(ModelerMode mode) {
                _cubit
                  ..mode(mode)
                  // The armed tool belongs to the mode it came from, so a mode change
                  // arms that mode's pointer rather than leaving a tool id from the
                  // old one that nothing here would recognise.
                  ..tool(
                    toolsFor(mode).isEmpty ? null : toolsFor(mode).first.id,
                  );
              }

              return LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) =>
                    switch (LayoutClass.of(constraints.maxWidth)) {
                      LayoutClass.desktop => ModelerShell(
                        mode: state.mode,
                        onMode: onMode,
                        submode: state.submode,
                        onSubmode: _cubit.submode,
                        activeTool: state.tool,
                        onTool: _ranTool,
                        actions: actions,
                        status: status,
                        properties: properties,
                        viewport: viewport,
                        documentName: state.documentName,
                        isDirty: state.history.isDirty,
                      ),
                      LayoutClass.tablet => ModelerTabletShell(
                        mode: state.mode,
                        onMode: onMode,
                        submode: state.submode,
                        onSubmode: _cubit.submode,
                        activeTool: state.tool,
                        onTool: _ranTool,
                        actions: actions,
                        status: status,
                        properties: properties,
                        viewport: viewport,
                      ),
                      LayoutClass.phone => ModelerPhoneShell(
                        mode: state.mode,
                        onMode: onMode,
                        submode: state.submode,
                        onSubmode: _cubit.submode,
                        activeTool: state.tool,
                        onTool: _ranTool,
                        actions: actions,
                        status: status,
                        properties: properties,
                        viewport: viewport,
                      ),
                    },
              );
            },
          ),
        ),
      ),
    ),
  };
}
