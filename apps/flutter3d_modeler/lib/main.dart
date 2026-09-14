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
import 'src/ui/export_anyway_dialog.dart';
import 'src/ui/export_screen.dart';
import 'src/ui/import_screen.dart';
import 'src/ui/lathe_dialog.dart';
import 'src/ui/material_studio_dialog.dart';
import 'src/ui/measurement_report_overlay.dart';
import 'src/ui/modeler_keys.dart';
import 'src/ui/properties/properties_panel.dart';
import 'src/ui/restore_autosave_dialog.dart';
import 'src/ui/save_as_dialog.dart';
import 'src/ui/screen_parts.dart';
import 'src/ui/shell_for_width.dart';
import 'src/ui/shortcut_help_screen.dart';
import 'src/ui/start_screen.dart';
import 'src/ui/status_line.dart';
import 'src/ui/theme.dart';
import 'src/ui/tools.dart';
import 'src/ui/top_bar_actions.dart';
import 'src/ui/unsaved_changes_dialog.dart';
import 'src/viewport_metrics.dart';

part 'src/screen/close_and_recovery.dart';
part 'src/screen/device.dart';
part 'src/screen/files.dart';
part 'src/screen/ready_parts.dart';

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
}
