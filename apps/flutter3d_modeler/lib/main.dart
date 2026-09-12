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
import 'dart:ui' as ui show AppExitResponse;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_screens/flutter3d_screens.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'src/autosaving.dart';
import 'src/backend.dart';
import 'src/churn_run.dart';
import 'src/close_beforeunload.dart';
import 'src/close_guard.dart';
import 'src/display_modes.dart';
import 'src/element_picking.dart';
import 'src/environment_summary.dart';
import 'src/exporting.dart';
import 'src/files/project_files.dart';
import 'src/files/sandbox_probe.dart';
import 'src/ground_grid.dart';
import 'src/import_plan.dart';
import 'src/material_pool.dart' show clay;
import 'src/modeler_cubit.dart';
import 'src/modeler_viewport.dart';
import 'src/object_picking.dart';
import 'src/opening.dart';
import 'src/orbit_run.dart';
import 'src/orientation_dial.dart';
import 'src/recent_projects.dart';
import 'src/report_problem.dart';
import 'src/selection_box.dart';
import 'src/staging.dart';
import 'src/transform_fields.dart';
import 'src/transform_gizmo.dart';
import 'src/transform_modal.dart';
import 'src/ui/export_screen.dart';
import 'src/ui/import_screen.dart';
import 'src/ui/lathe_dialog.dart';
import 'src/ui/layout_class.dart';
import 'src/ui/material_studio_dialog.dart';
import 'src/ui/modifier_stack_panel.dart';
import 'src/ui/number_field.dart';
import 'src/ui/operation_card.dart';
import 'src/ui/properties_sections.dart';
import 'src/ui/section_label.dart';
import 'src/ui/selection_key_bindings.dart';
import 'src/ui/shell.dart';
import 'src/ui/shell_phone.dart';
import 'src/ui/shell_tablet.dart';
import 'src/ui/shortcut_help_screen.dart';
import 'src/ui/start_screen.dart';
import 'src/ui/status_line.dart';
import 'src/ui/theme.dart';
import 'src/ui/tools.dart';
import 'src/ui/undo_redo_buttons.dart';

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

void main() => runApp(const ModelerApp());

class ModelerApp extends StatelessWidget {
  const ModelerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'flutter3d modeller',
    debugShowCheckedModeBanner: false,
    theme: modelerTheme(),
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
Future<ProjectOpened?> findRecovery(BinaryStorage storage, String sessionId) async {
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

  /// The measured camera move, when the build asked for one.
  OrbitRun? _orbit;

  /// What the last frame's `render` cost, which the run records against the
  /// wall clock the ticker reports.
  int? _lastRenderMicros;

  /// Milliseconds from opening the device to the first frame being ready.
  int _openedInMs = 0;

  /// The edit-convert-upload loop, when the build asked for one.
  ChurnRun? _churn;

  /// The device, kept so a model opened later can be uploaded through it.
  GraphicsDevice? _device;

  /// What the last file operation said, shown beside the buttons.

  /// Which lens the viewport looks through, and what the surface is drawn as.
  ViewLens _lens = ViewLens.perspective;
  ShadingMode _shading = ShadingMode.material;

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
  MeshPicker? _picker;
  int _pickerVersion = -1;

  MeshPicker? get _elementPicker {
    final EditMesh? mesh = _editMesh;
    final int? id = _history.selection.activeObject;
    if (mesh == null || id == null) return null;
    final int version = _history.project[id]!.version;
    if (_picker == null || _pickerVersion != version) {
      final plan = MeshLayoutPlan()..build(mesh);
      _picker = MeshPicker(mesh, MeshBvh(mesh, plan));
      _pickerVersion = version;
    }
    return _picker;
  }

  /// What the last operation said when it refused, shown in the status line
  /// until something else happens.

  /// The tick the last frame was at, so a turn advances by real time rather
  /// than by frames — a view that swings faster on a fast machine is a view
  /// nobody can aim.
  Duration _lastTick = Duration.zero;

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
      storage: widget.autosaveStorage ?? defaultBinaryStorage('flutter3d_modeler'),
      sessionId: _kAutosaveSessionId,
      onIssue: (String said) => _cubit.say(said, important: true),
    );
    unawaited(_open());
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    installBeforeUnloadGuard(() => _history.isDirty);
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
          onPressed: () =>
              Navigator.of(context).pop(UnsavedChoice.keepEditing),
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
    }
    _churn?.step();
    final run = _orbit;
    if (run != null) {
      run.step(elapsed.inMicroseconds, _lastRenderMicros);
      if (run.done) {
        // To stderr through `debugPrint`, which is what reaches a browser's
        // console as well as a terminal — the same line on every platform this
        // is measured on.
        final said = OrbitRun.describe(
          run.report(),
          what: kStress > 0
              ? '$kStress triangles in $kStressObjects draws'
              : (kModel.isEmpty ? 'the cube' : kModel),
        );
        final churn = _churn;
        final whole = churn == null
            ? '$said\n  opened in    $_openedInMs ms'
            : '$said\n  opened in    $_openedInMs ms\n${churn.describe()}';
        debugPrint(whole);
        _report = whole;
        _churn = null;
        _orbit = null;
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _timings.stop();
    _autosave?.dispose();
    _lifecycle.dispose();
    _cubit.close();
    super.dispose();
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
      // true there, so this is the resolution the browser scales from. Impeller
      // ignores it and sizes itself per frame.
      final device = await openDevice(width: 1600, height: 1000);
      if (!mounted) return;
      _device = device;
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
          _churn = ChurnRun(device: device, node: node, from: source);
        }
      }
      opening.stop();
      _openedInMs = opening.elapsedMilliseconds;
      if (kOrbit > 0) _orbit = OrbitRun(frames: kOrbit, stage: stage);
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
      setState(() {
        // With no run to wait for, the opening cost is the whole report.
        if (kOrbit <= 0) _report = 'opened in $_openedInMs ms';
      });
      if (kModel.isEmpty && kOrbit <= 0 && !kSandboxProbe) {
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
          '(${_count(read.project.objects.length, 'object')}).',
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
      await storage.remove(recoveryPathFor(null, sessionId: _kAutosaveSessionId));
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
      _picker = null;
      _pickerVersion = -1;
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
      final opening = Stopwatch()..start();
      final opened = await _openBytesWithImportScreen(
        picked.name,
        picked.bytes,
        device,
      );
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
          final said =
              '${picked.name}: '
              '${_count(project.objects.length, 'object')}, '
              '${_count(project.triangleCount, 'triangle')}, '
              '${_count(project.materials.length, 'material')}, '
              'opened in ${opening.elapsedMilliseconds} ms';
          _cubit.opened(
            ModelHistory(project),
            renderer: (_state as ModelerReady).renderer,
            stage: stage,
            documentName: picked.name,
            said: <String>[said, ...opened.warnings].join('\n'),
          );
          setState(() {
            // Ids start again in the new project, so a picker held against the
            // old one could match a version and answer about a mesh that is
            // gone.
            _picker = null;
            _pickerVersion = -1;
          });
      }
    } catch (error) {
      if (mounted) _cubit.say('could not open it: $error');
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

  /// "1 object" and "2 objects", because a status line that says "1 objects"
  /// reads as something a program wrote rather than as a sentence.
  static String _count(int n, String one) => '$n $one${n == 1 ? '' : 's'}';

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
  /// Answers whether bytes actually landed on disk — `ui-24`'s own
  /// "неудачная запись не закрывает" needs to know, not just report.
  Future<bool> _saveFile() async {
    if (_state is! ModelerReady) return false;

    final Uint8List bytes;
    try {
      bytes = writeProject(_history.project);
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
          _cubit.say(<String>[...said, ...warnings].join('\n'), important: true);
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
          final said =
              '${picked.name}: '
              '${_count(project.objects.length, 'object')}, '
              '${_count(project.triangleCount, 'triangle')}, '
              '${_count(project.materials.length, 'material')}, '
              'opened in ${opening.elapsedMilliseconds} ms';
          _cubit.opened(
            ModelHistory(project),
            renderer: (_state as ModelerReady).renderer,
            stage: stage,
            documentName: picked.name,
            said: <String>[said, ...opened.warnings].join('\n'),
          );
          setState(() {
            _picker = null;
            _pickerVersion = -1;
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
      case OpenedModel(
        :final ModelProject project,
        :final ModelerStage stage,
      ):
        stage.frameSubject();
        _surfaces.forget();
        final said =
            '$name: '
            '${_count(project.objects.length, 'object')}, '
            '${_count(project.triangleCount, 'triangle')}, '
            '${_count(project.materials.length, 'material')}, '
            'opened in ${opening.elapsedMilliseconds} ms';
        _cubit.opened(
          ModelHistory(project),
          renderer: (_state as ModelerReady).renderer,
          stage: stage,
          documentName: name,
          said: <String>[said, ...opened.warnings].join('\n'),
        );
        setState(() {
          _picker = null;
          _pickerVersion = -1;
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
      _picker = null;
      _pickerVersion = -1;
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

  /// A drag with a transform tool armed.
  ///
  /// **The drag is in pixels and the model is in metres**, so the conversion
  /// goes through the same pixel size the overlay uses — which is what makes a
  /// vertex follow the pointer rather than lag behind it or run ahead. Rotation
  /// and scale take the drag as an amount rather than as a direction, because
  /// without an axis to constrain them there is nothing else it could mean;
  /// the axis arrives with the gizmo.
  void _dragged(Offset delta, double viewportHeight) {
    final state = _state;
    final String? tool = _tool;
    if (state is! ModelerReady || tool == null) return;
    if (!kDragTools.contains(tool)) return;
    if (_history.selection.isEmpty) return;

    _lastViewportHeight = viewportHeight;
    final look = state.stage.overlayView(viewportHeight);
    final TransformModal modal = _modalFor(tool);

    // Pixels into whatever the transform is measured in. A move is metres at
    // the depth the selection is at — a pixel is a different number of metres a
    // metre further away — and a turn and a scale are a hundredth per pixel,
    // which is the sensitivity every modeller settles on.
    if (modal.kind == TransformKind.move) {
      final vm.Vector3 middle = _middleOfSelection();
      final double metres =
          look.pixel * (look.perspective ? (middle - look.eye).length : 1.0);
      modal.dragged +=
          look.right * (delta.dx * metres) + look.up * (-delta.dy * metres);
    } else {
      // One number, carried on whichever component the constraint lets
      // through, so `amount` can zero the rest the same way it does for a move.
      final double by = delta.dx * 0.01;
      modal.dragged += switch (modal.axis) {
        TransformAxis.y => vm.Vector3(0, by, 0),
        TransformAxis.z => vm.Vector3(0, 0, by),
        _ => vm.Vector3(by, 0, 0),
      };
    }
    _applyModal(modal, look);
  }

  /// What the viewport reports when the pointer goes up: the transform is
  /// accepted, which is what letting go of a drag means.
  void _endDrag() => _commitModal();

  /// A key arrived while a transform is going on.
  ///
  /// Returns whether it was taken. The keys are the ones every modeller has:
  /// `X`/`Y`/`Z` constrain, digits and a point and a minus type a number,
  /// backspace takes one off, Enter accepts and Escape throws it away.
  bool _modalKey(LogicalKeyboardKey key, String? character) {
    final TransformModal? modal = _modal;
    if (modal == null) return false;
    if (key == LogicalKeyboardKey.escape) {
      _cancelModal();
      return true;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _commitModal();
      return true;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (!modal.type('backspace')) return false;
      _reapply(modal);
      return true;
    }
    final TransformAxis? pressed = switch (key) {
      LogicalKeyboardKey.keyX => TransformAxis.x,
      LogicalKeyboardKey.keyY => TransformAxis.y,
      LogicalKeyboardKey.keyZ => TransformAxis.z,
      _ => null,
    };
    if (pressed != null) {
      modal.axis = modal.axis.pressed(pressed);
      _reapply(modal);
      return true;
    }
    if (character != null && modal.type(character)) {
      _reapply(modal);
      return true;
    }
    return false;
  }

  /// Re-runs the transform at whatever it is now, after a key changed it.
  void _reapply(TransformModal modal) {
    final state = _state;
    if (state is! ModelerReady) return;
    _applyModal(modal, state.stage.overlayView(_lastViewportHeight));
  }

  /// The height the picture was laid out at, kept so a key press can measure a
  /// pixel the same way a pointer move does.
  double _lastViewportHeight = 600;

  /// The transform in progress, or null.
  ///
  /// **One object for the pointer and the keyboard both**, because they are the
  /// same transform: a person presses `G`, moves the mouse, presses `X`, types
  /// `5` and presses Enter, and every one of those changes the same thing.
  /// Two paths would answer differently on the frame the constraint arrives.
  TransformModal? _modal;

  /// Starts one if there is not one already, opening the transaction it will
  /// be committed or thrown away as.
  TransformModal _modalFor(String tool) {
    final TransformModal? going = _modal;
    if (going != null) return going;
    _history.beginTransaction();
    return _modal = TransformModal(switch (tool) {
      'mesh.rotate' || 'object.rotate' => TransformKind.rotate,
      'mesh.scale' || 'object.scale' => TransformKind.scale,
      _ => TransformKind.move,
    });
  }

  /// A gizmo arm was grabbed: the same transform `G` starts, with the axis it
  /// was grabbed by already set.
  ///
  /// **One path, not two.** The alternative — a gizmo that computes its own
  /// delta and runs its own command — would be a second answer to what a move
  /// is, and the two would part company at the first snap, the first pivot
  /// setting and the first refusal. Here the arm only says which axis; the drag
  /// after it is the drag `G X` already had, and it ends in the same one step
  /// of history.
  void _grabbedGizmo(GizmoAxis axis) {
    if (_state is! ModelerReady) return;
    final String tool = switch (_gizmoKind) {
      TransformKind.rotate => 'object.rotate',
      TransformKind.scale => 'object.scale',
      TransformKind.move => 'object.move',
    };
    final modal = _modalFor(tool);
    modal.axis = switch (axis) {
      GizmoAxis.x => TransformAxis.x,
      GizmoAxis.y => TransformAxis.y,
      GizmoAxis.z => TransformAxis.z,
    };
    _cubit.say(modal.says);
  }

  /// Which gizmo the armed tool asks for.
  TransformKind get _gizmoKind => switch (_tool) {
    'mesh.rotate' || 'object.rotate' => TransformKind.rotate,
    'mesh.scale' || 'object.scale' => TransformKind.scale,
    _ => TransformKind.move,
  };

  /// Where the gizmo stands, or null when nothing is selected.
  ///
  /// Null rather than the origin: a gizmo at the world centre with nothing
  /// selected is a control that does nothing, drawn where a person will aim at
  /// it.
  vm.Vector3? get _gizmoPivot =>
      _history.selection.isEmpty ? null : _middleOfSelection();

  /// Accepts the transform. The transaction closes and its one step stays.
  void _commitModal() {
    if (_modal == null) return;
    _modal = null;
    _history.endTransaction();
    _cubit.say(null);
  }

  /// Throws it away.
  ///
  /// **Undone rather than reversed.** The opposite of a scale by 0.3 is a scale
  /// by ten thirds, and the two do not compose back to the identity in floating
  /// point — so Escape closes the transaction, takes its one step back and
  /// drops it, which puts the document back by pointer.
  void _cancelModal() {
    if (_modal == null) return;
    _modal = null;
    _history.endTransaction();
    if (_history.undo()) {
      _history.dropRedo();
      _sync();
    }
    _cubit.say('cancelled');
  }

  /// Applies whatever the transform is at now, replacing what it applied last.
  ///
  /// Inside the open transaction, so a hundred of these are one step. Each one
  /// runs the *difference* from the last, because a command moves by an amount
  /// rather than to a place.
  void _applyModal(
    TransformModal modal,
    ({
      vm.Vector3 eye,
      vm.Vector3 right,
      vm.Vector3 up,
      double pixel,
      bool perspective,
    })
    look,
  ) {
    final vm.Vector3 want = modal.amount;
    final vm.Vector3 step = want - _appliedSoFar;
    _appliedSoFar = vm.Vector3.copy(want);
    if (step.length2 == 0) {
      _cubit.say(modal.says);
      return;
    }

    final bool mesh = _history.selection.mode == SelectionMode.mesh;
    final double scalar = step.x + step.y + step.z;
    // **The pivot is the command's, not this file's.** `TransformElements`
    // takes the median of the selected vertices itself and sandwiches the
    // matrix in it, so wrapping the matrix here as well turned and scaled about
    // twice the median — a mesh-mode turn swung the geometry off into space,
    // and nothing on either side of the seam caught it because the command's
    // own pivot had no test. What is handed over is the bare rotation or the
    // bare scale.
    final ModelCommand command = switch (modal.kind) {
      TransformKind.move =>
        mesh ? TransformElements(vm.Matrix4.translation(step)) : MoveBy(step),
      TransformKind.rotate =>
        mesh
            ? TransformElements(
                vm.Matrix4.compose(
                  vm.Vector3.zero(),
                  vm.Quaternion.axisAngle(_axisOf(modal, look), scalar),
                  vm.Vector3.all(1),
                ),
                what: 'turn',
              )
            : RotateBy(axis: _axisOf(modal, look), radians: scalar),
      TransformKind.scale =>
        mesh
            ? TransformElements(
                vm.Matrix4.diagonal3(vm.Vector3.all(1 + scalar)),
                what: 'scale',
              )
            : ScaleBy(1 + scalar),
    };
    _cubit.ran(command, said: modal.says);
  }

  /// How much of the transform has been applied to the document already.
  vm.Vector3 _appliedSoFar = vm.Vector3.zero();

  /// The axis a turn goes about: the constrained one, or the view direction.
  vm.Vector3 _axisOf(
    TransformModal modal,
    ({
      vm.Vector3 eye,
      vm.Vector3 right,
      vm.Vector3 up,
      double pixel,
      bool perspective,
    })
    look,
  ) => switch (modal.axis) {
    TransformAxis.x => vm.Vector3(1, 0, 0),
    TransformAxis.y => vm.Vector3(0, 1, 0),
    TransformAxis.z => vm.Vector3(0, 0, 1),
    // Unconstrained, a turn goes about the axis the camera is looking down, so
    // a horizontal drag turns the model the way the hand went whatever angle it
    // is being seen from.
    _ => (look.eye - _middleOfSelection()).normalized(),
  };

  /// The middle of what is selected, in world units.
  vm.Vector3 _middleOfSelection() {
    final selection = _history.selection;
    if (selection.mode == SelectionMode.mesh) {
      final EditMesh? mesh = _editMesh;
      if (mesh == null) return vm.Vector3.zero();
      return medianOf(mesh, selection.asMeshSelection);
    }
    final middle = vm.Vector3.zero();
    var counted = 0;
    for (final int id in selection.objects) {
      final object = _history.project[id];
      if (object == null) continue;
      middle.add(object.transform.getTranslation());
      counted++;
    }
    return counted == 0 ? middle : (middle..scale(1 / counted));
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
      // opens `lathe_dialog.dart` rather than going through `_commandFor`,
      // which only ever answers with a command ready to run immediately.
      _cubit.tool(id);
      unawaited(_openLatheDialog());
      return;
    }
    final ModelCommand? command = _commandFor(id);
    if (command == null) {
      _cubit.tool(id);
      return;
    }
    _cubit
      ..tool(id)
      ..ran(command);
  }

  /// The command a rail button stands for, or null when it only arms.
  ///
  /// **One switch in one place, which is what the tool table was built to
  /// allow.** A callback on each row of that table would put this decision in
  /// as many places as there are tools, and a tool added without one would be a
  /// button that silently did nothing.
  ModelCommand? _commandFor(String id) => switch (id) {
    'object.add' => const AddPrimitive(kind: 'box'),
    'object.duplicate' => const DuplicateObjects(),
    'object.delete' => const DeleteObjects(),
    'object.bake' => switch (_history.selection.activeObject) {
      final int selected => BakeToMesh(selected),
      _ => null,
    },
    'object.origin' => switch (_history.selection.activeObject) {
      final int selected => SetOrigin(
        id: selected,
        to: OriginPlacement.boundsBottom,
      ),
      _ => null,
    },
    'object.apply' => switch (_history.selection.activeObject) {
      final int selected => ApplyTransform(selected),
      _ => null,
    },
    'mesh.extrude' => Extrude(_stepOf()),
    'mesh.loopCut' => const LoopCut(),
    'mesh.triangulate' => const Triangulate(),
    'mesh.separate' => const Separate(),
    'mesh.dissolve' => const DissolveEdges(),
    'mesh.merge' => const MergeByDistance(),
    'mesh.normals' => const RecalculateNormals(),
    'mesh.flip' => const RecalculateNormals(flip: true),
    'mesh.delete' => const DeleteElements(),
    _ => null,
  };

  /// How far an extrusion goes when nobody has said.
  ///
  /// A tenth of the model rather than a fixed number of metres: the same button
  /// is pressed on a cube of one metre and on a scanned head of two hundred,
  /// and a fixed distance is invisible on one and catastrophic on the other.
  double _stepOf() {
    final EditMesh? mesh = _editMesh;
    if (mesh == null) return 0.1;
    final low = vm.Vector3.all(double.infinity);
    final high = vm.Vector3.all(double.negativeInfinity);
    final at = vm.Vector3.zero();
    var found = false;
    for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
      if (!mesh.isVertexAlive(vertex)) continue;
      found = true;
      mesh.positionOf(vertex, at);
      vm.Vector3.min(low, at, low);
      vm.Vector3.max(high, at, high);
    }
    if (!found) return 0.1;
    final span = (high - low).length;
    return span == 0.0 ? 0.1 : span * 0.1;
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
                if (frustum.containsVector3(node.worldBounds.center))
                  object.id,
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

  /// Brings the scene to the project.
  ///
  /// The one place left that changes the document without a command going
  /// through the cubit: a drag that closed its own transaction, and an `amend`.
  /// Both tell the cubit afterwards, and it does the rest.
  void _sync() => _cubit.documentMoved();

  /// Nine numbers typed into the panel.
  ///
  /// `SetTransform` rather than `MoveBy`, because what a field says is where
  /// the object goes rather than how far it moves — a person who types the same
  /// number twice expects nothing to happen the second time, and a panel that
  /// emitted a difference would move the object again on every rebuild.
  void _setTransform(int id, TransformFields to) {
    if (_history.project[id] == null) return;
    final built = transformFromFields(to);
    if (built.refused case final String said) {
      _cubit.say(said);
      return;
    }
    _cubit.ran(SetTransform(id: id, to: built.matrix!));
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
    final List<int> next;
    if (id == null) {
      if (pick is PickedService) return;
      next = extend ? was.objects : const <int>[];
    } else if (!extend) {
      next = <int>[id];
    } else if (was.objects.contains(id)) {
      next = <int>[
        for (final int each in was.objects)
          if (each != id) each,
      ];
    } else {
      next = <int>[...was.objects, id];
    }

    // Compared before setting, because a click on the background with nothing
    // selected is the commonest click there is and it changes nothing: a frame
    // rebuilt for it is a frame spent on an answer of "still nothing".
    if (next.length == was.objects.length && next.every(was.objects.contains)) {
      return;
    }
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
  Widget build(BuildContext context) => BlocBuilder<ModelerCubit, ModelerState>(
    bloc: _cubit,
    builder: (BuildContext context, ModelerState state) => _screen(state),
  );

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
        child: _Keys(
      onKey: _modalKey,
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
            UndoRedoButtons(
              canUndo: state.history.canUndo,
              canRedo: state.history.canRedo,
              undoSays: state.history.undoSays,
              redoSays: state.history.redoSays,
              onUndo: _undo,
              onRedo: _redo,
            ),
            const SizedBox(width: 4),
            // **A menu rather than five buttons on the rail.** The rail is for
            // the tools a hand rests on; adding a shape is something done once
            // and then not again for an hour, and five of anything on a rail of
            // fifty-two pixels is a rail nobody can read. `A` still adds a box,
            // which is the one people reach for without looking.
            PopupMenuButton<String>(
              tooltip: 'Add a primitive',
              onSelected: (String kind) => _cubit.ran(AddPrimitive(kind: kind)),
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                for (final String kind in AddPrimitive.primitiveKinds)
                  PopupMenuItem<String>(
                    value: kind,
                    height: ModelerMetrics.row,
                    child: Text(kind, style: const TextStyle(fontSize: 13)),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text('Add', style: TextStyle(fontSize: 13)),
              ),
            ),
            TextButton(onPressed: _openFile, child: const Text('Open')),
            const SizedBox(width: 4),
            FilledButton.tonal(onPressed: _saveFile, child: const Text('Save')),
            const SizedBox(width: 4),
            PopupMenuButton<ExportFormat>(
              tooltip: 'Export a copy',
              onSelected: _exportFile,
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<ExportFormat>>[
                    for (final ExportFormat format in ExportFormat.values)
                      PopupMenuItem<ExportFormat>(
                        value: format,
                        height: ModelerMetrics.row,
                        child: Text(
                          '${format.suffix}  ${format.says}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text('Export', style: TextStyle(fontSize: 13)),
              ),
            ),
            // `mat-15`'s own entry: a preview tool rather than a command,
            // so it sits beside Export rather than on the object tool
            // rail — nothing it opens is a shape to add to the document.
            MergeSemantics(
              child: Semantics(
                label: 'Material Studio',
                button: true,
                child: IconButton(
                  tooltip: 'Material Studio — preview a material',
                  onPressed: () => unawaited(_openMaterialStudio()),
                  icon: const Icon(Icons.tonality_outlined, size: 20),
                ),
              ),
            ),
            // `ui-23`'s own pass: `IconButton.tooltip` sets
            // `SemanticsNode.tooltip`, not `.label`. `MergeSemantics`
            // folds the label below down onto the button's own inner,
            // actually-tappable node.
            MergeSemantics(
              child: Semantics(
                label: 'Keyboard shortcuts',
                button: true,
                child: IconButton(
                  tooltip: 'Keyboard shortcuts (?)',
                  onPressed: _showShortcutHelp,
                  icon: const Icon(Icons.help_outline, size: 20),
                ),
              ),
            ),
            MergeSemantics(
              child: Semantics(
                label: 'Start screen',
                button: true,
                child: IconButton(
                  tooltip:
                      'Start screen — open a file or start a new project',
                  onPressed: () => unawaited(_showStartScreen()),
                  icon: const Icon(Icons.home_outlined, size: 20),
                ),
              ),
            ),
            MergeSemantics(
              child: Semantics(
                label: 'Report a problem',
                button: true,
                child: IconButton(
                  tooltip: 'Report a problem',
                  onPressed: _reportProblem,
                  icon: const Icon(Icons.bug_report_outlined, size: 20),
                ),
              ),
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
          final properties = _Properties(
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
            onRename: (int id, String to) => _cubit.ran(Rename(id: id, to: to)),
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
            lastCommand: state.history.journal.isEmpty
                ? null
                : state.history.journal.last,
            onAmend: _amend,
            shading: _shading,
            onShading: (ShadingMode mode) => setState(() => _shading = mode),
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
                  // One or the other, never both: a click in the mesh mode is a
                  // question about this mesh's elements and is answered on the
                  // CPU, and asking the renderer for a node as well would cost a
                  // whole frame to answer a question nobody asked.
                  onPick: _mode == ModelerMode.mesh ? null : _picked,
                  onElementPick: _mode == ModelerMode.mesh && _editMesh != null
                      ? _pickedElement
                      : null,
                  // One or the other: with a transform tool armed a left drag is
                  // the transform, and with none it is a rectangle. A viewport
                  // that offered both would have to guess, and the guess would be
                  // wrong on the frame a person changed their mind.
                  onDragTool: kDragTools.contains(_tool) ? _dragged : null,
                  onDragDone: _endDrag,
                  onBox: _boxed,
                  // The gizmo stands on the selection and offers the transform
                  // the armed tool asks for. On a tablet it is the only way in:
                  // there is no `G` key on an iPad, so this is not a second path
                  // to the same place — on three of the five platforms phase 1
                  // ships to it is the path.
                  gizmoPivot: _gizmoPivot,
                  gizmoKind: _gizmoKind,
                  onGizmoDrag: _grabbedGizmo,
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
                          if (stage.sync?.nodeOf(id) case final SceneNode n) n,
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
                Positioned(
                  left: 12,
                  top: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xCC000000),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        said,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontFamilyFallback: <String>['Courier'],
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );

          void onMode(ModelerMode mode) {
            _cubit
              ..mode(mode)
              // The armed tool belongs to the mode it came from, so a mode change
              // arms that mode's pointer rather than leaving a tool id from the
              // old one that nothing here would recognise.
              ..tool(toolsFor(mode).isEmpty ? null : toolsFor(mode).first.id);
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

/// The right-hand panel: `ui-08`'s own object list, transform grid and
/// modifier stack, plus what the viewport knows about display and camera.
///
/// **No longer as thin as the row that first drew it.** An earlier draft of
/// this comment called the panel thin on purpose, waiting on `doc-03`/
/// `doc-05` before an object list or a number field could edit a
/// `ModelProject` through a command at all — both are done now, `doc-06` and
/// `doc-23` besides, and `_ObjectRow`/`_TransformRows`/`ModifierStackPanel`
/// below are what a panel free to write to the document actually looks like.
class _Properties extends StatelessWidget {
  const _Properties({
    required this.mode,
    required this.stage,
    required this.project,
    required this.selection,
    required this.onSelect,
    required this.onTransform,
    required this.onRename,
    required this.onToggleModifier,
    required this.onReorderModifier,
    required this.onAddModifier,
    required this.lastCommand,
    required this.onAmend,
    required this.shading,
    required this.onShading,
    required this.lens,
    required this.onLens,
    required this.onView,
  });

  /// **`ui-04`'s own "content is replaced wholesale."** Object mode wants the
  /// object list, the transform grid and the modifier stack; mesh mode wants
  /// the last-operation card and the selection summary. Display/View/Budget
  /// are cross-mode utility — the camera and the export budget mean the same
  /// thing regardless of what is being edited — so they stay in every mode
  /// rather than disappearing along with the mode-specific sections.
  final ModelerMode mode;

  final ModelerStage stage;
  final ModelProject project;
  final ProjectSelection selection;
  final ValueChanged<int> onSelect;

  /// A number field was committed: the whole transform, as nine numbers.
  final void Function(int id, TransformFields to) onTransform;

  /// The name box was committed.
  final void Function(int id, String to) onRename;

  /// A modifier's own enabled switch was flipped.
  final void Function(int id, int index) onToggleModifier;

  /// A modifier was dragged to a new place in the stack.
  final void Function(int id, int from, int to) onReorderModifier;

  /// The stack's own "Add" link was pressed, for the held object.
  final ValueChanged<int> onAddModifier;

  /// What the operation card is showing, and where an adjustment goes.
  final ModelCommand? lastCommand;
  final ValueChanged<ModelCommand> onAmend;

  final ShadingMode shading;
  final ValueChanged<ShadingMode> onShading;
  final ViewLens lens;
  final ValueChanged<ViewLens> onLens;
  final ValueChanged<StandardView> onView;

  @override
  Widget build(BuildContext context) {
    final mesh = switch (project[selection.activeObject ?? -1]?.geometry) {
      EditedGeometry(:final mesh) => mesh,
      _ => null,
    };
    final held = project[selection.activeObject ?? -1];
    final sections = sectionsFor(mode);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      children: <Widget>[
        SectionLabel('Display'),
        SegmentedButton<ShadingMode>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<ShadingMode>>[
            ButtonSegment<ShadingMode>(
              value: ShadingMode.material,
              label: Text('Material'),
            ),
            ButtonSegment<ShadingMode>(
              value: ShadingMode.normals,
              label: Text('Normals'),
            ),
            ButtonSegment<ShadingMode>(
              value: ShadingMode.wireframe,
              label: Text('Wire'),
            ),
          ],
          selected: <ShadingMode>{shading},
          onSelectionChanged: (Set<ShadingMode> picked) =>
              onShading(picked.first),
        ),
        const SizedBox(height: 8),
        SegmentedButton<ViewLens>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<ViewLens>>[
            ButtonSegment<ViewLens>(
              value: ViewLens.perspective,
              label: Text('Perspective'),
            ),
            ButtonSegment<ViewLens>(
              value: ViewLens.orthographic,
              label: Text('Orthographic'),
            ),
          ],
          selected: <ViewLens>{lens},
          onSelectionChanged: (Set<ViewLens> picked) => onLens(picked.first),
        ),
        SectionLabel('View'),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: <Widget>[
            for (final StandardView view in StandardView.values)
              OutlinedButton(
                onPressed: () => onView(view),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, ModelerMetrics.row - 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: Text(_viewNames[view]!),
              ),
          ],
        ),
        if (sections.contains(PropertiesSection.objects)) ...<Widget>[
          SectionLabel('Objects'),
          for (final ModelObject object in project.objects)
            _ObjectRow(
              object: object,
              selected: selection.objects.contains(object.id),
              onTap: () => onSelect(object.id),
            ),
        ],
        if (held != null &&
            sections.contains(PropertiesSection.transform)) ...<Widget>[
          SectionLabel('Transform'),
          _NameField(
            key: ValueKey<int>(held.id),
            name: held.name,
            onRenamed: (String to) => onRename(held.id, to),
          ),
          const SizedBox(height: 4),
          _TransformRows(
            key: ValueKey<int>(held.id),
            fields: transformFieldsOf(held.transform),
            onChanged: (TransformFields to) => onTransform(held.id, to),
          ),
        ],
        if (held != null &&
            sections.contains(PropertiesSection.modifiers)) ...<Widget>[
          SectionLabel('Modifiers'),
          ModifierStackPanel(
            key: ValueKey<int>(held.id),
            slots: held.modifiers,
            onToggle: (int index) => onToggleModifier(held.id, index),
            onReorder: (int from, int to) =>
                onReorderModifier(held.id, from, to),
            onAdd: () => onAddModifier(held.id),
          ),
        ],
        if (sections.contains(PropertiesSection.lastOperation)) ...<Widget>[
          SectionLabel('Last operation'),
          OperationCard(command: lastCommand, onAmend: onAmend),
        ],
        if (sections.contains(PropertiesSection.selection)) ...<Widget>[
          SectionLabel('Selection'),
          _Row('What', selection.says),
        ],
        if (mesh != null &&
            sections.contains(PropertiesSection.mesh)) ...<Widget>[
          SectionLabel('Mesh'),
          _Row('Vertices', '${mesh.vertexCount}'),
          _Row('Faces', '${mesh.faceCount}'),
        ],
        SectionLabel('Budget'),
        _Row('Triangles', '${project.triangleCount}'),
        _Row('Profile', project.profile.name),
      ],
    );
  }

  static const Map<StandardView, String> _viewNames = <StandardView, String>{
    StandardView.front: 'Front',
    StandardView.back: 'Back',
    StandardView.left: 'Left',
    StandardView.right: 'Right',
    StandardView.top: 'Top',
    StandardView.bottom: 'Bottom',
  };
}

/// Position, turn and size, three numbers each.
///
/// **Keyed by the object's id at the call site**, for the reason the name field
/// is: a rebuild for a different object must build different boxes rather than
/// rewrite the text under a cursor.
///
/// The turn and the size are shown as `transformFieldsOf` reads them out of the
/// matrix, which is not always the spelling somebody typed — a turn of 30, 90,
/// 30 reads back as 60, 90, 0, because at the pole the X and Z turns are the
/// same turn and only their difference survives. That is a property of Euler
/// angles rather than of this panel, and the file that does the arithmetic
/// argues it at length.
class _TransformRows extends StatelessWidget {
  const _TransformRows({
    super.key,
    required this.fields,
    required this.onChanged,
  });

  final TransformFields fields;
  final ValueChanged<TransformFields> onChanged;

  static const List<String> _axisLabels = <String>['X', 'Y', 'Z'];
  static const List<String> _rowLabels = <String>['Position', 'Rotation', 'Scale'];

  /// [fields], with [row]'s own [axis] component replaced by [to] — the one
  /// piece three separate `VectorField` callbacks used to reassemble, now
  /// done in one place since a grid cell only ever changes one number.
  TransformFields _withAxis(int row, int axis, double to) {
    vm.Vector3 replace(vm.Vector3 v) => vm.Vector3(
      axis == 0 ? to : v.x,
      axis == 1 ? to : v.y,
      axis == 2 ? to : v.z,
    );
    return (
      position: row == 0 ? replace(fields.position) : fields.position,
      rotationDegrees: row == 1
          ? replace(fields.rotationDegrees)
          : fields.rotationDegrees,
      scale: row == 2 ? replace(fields.scale) : fields.scale,
    );
  }

  List<double> _rowValues(int row) => switch (row) {
    0 => <double>[fields.position.x, fields.position.y, fields.position.z],
    1 => <double>[
      fields.rotationDegrees.x,
      fields.rotationDegrees.y,
      fields.rotationDegrees.z,
    ],
    _ => <double>[fields.scale.x, fields.scale.y, fields.scale.z],
  };

  /// The hand-over's own "3x3 transform grid": `Position`/`Rotation`/`Scale`
  /// down the rows, `X`/`Y`/`Z` across the columns — a `Table`, not three
  /// stacked full-width fields, so a person can scan one axis across all
  /// three properties in one eyeful rather than hunting through nine rows.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final TextStyle? captionStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget axisHeader(String said) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(said, textAlign: TextAlign.center, style: captionStyle),
    );
    Widget rowLabel(String said) => Padding(
      padding: const EdgeInsets.only(top: 6, right: 4),
      child: Text(said, style: captionStyle),
    );

    return Table(
      columnWidths: const <int, TableColumnWidth>{
        0: FixedColumnWidth(56),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: <TableRow>[
        TableRow(
          children: <Widget>[
            const SizedBox.shrink(),
            for (final String axis in _axisLabels) axisHeader(axis),
          ],
        ),
        for (var row = 0; row < 3; row++)
          TableRow(
            children: <Widget>[
              rowLabel(_rowLabels[row]),
              for (var axis = 0; axis < 3; axis++)
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 4),
                  child: NumberField(
                    label: _axisLabels[axis],
                    showLabel: false,
                    semanticLabel: '${_rowLabels[row]} ${_axisLabels[axis]}',
                    value: _rowValues(row)[axis],
                    onChanged: (double to) =>
                        onChanged(_withAxis(row, axis, to)),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// The object's name, editable.
///
/// **Keyed by the object's id**, so selecting a different object builds a
/// different field rather than rewriting the text under a cursor — which is how
/// a rename ends up applied to whichever object happened to be selected when
/// the person pressed Enter.
class _NameField extends StatefulWidget {
  const _NameField({super.key, required this.name, required this.onRenamed});

  final String name;
  final void Function(String to) onRenamed;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.name,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_NameField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.name != old.name) _text.text = widget.name;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final String said = _text.text.trim();
    // An empty name is refused by the command with a sentence; putting the old
    // one back here as well means a person who clears the box and clicks away
    // is not left looking at a blank field for an object that still has a name.
    if (said.isEmpty || said == widget.name) {
      _text.text = widget.name;
      return;
    }
    widget.onRenamed(said);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: ModelerMetrics.row,
    child: Semantics(
      // The row it sits in already reads "Objects" above the list, but a
      // screen reader stepping field by field through the panel has no other
      // way to tell this box apart from a `NumberField`'s own bare value.
      label: 'Name',
      textField: true,
      child: TextField(
        controller: _text,
        focusNode: _focus,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _commit(),
        onTapOutside: (_) => _focus.unfocus(),
      ),
    ),
  );
}

/// One line of the object list: the name, what it is made of, and whether it is
/// selected.
///
/// **The kind is shown, because it decides what the rail can do.** An object
/// that is still a cylinder refuses every mesh command with a sentence about
/// converting it; showing which objects are parametric is what stops that
/// sentence being a surprise.
class _ObjectRow extends StatelessWidget {
  const _ObjectRow({
    required this.object,
    required this.selected,
    required this.onTap,
  });

  final ModelObject object;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // `ui-23`'s own pass: the row already showed selection with colour and
    // weight, which a screen reader cannot read. `button: true` names what a
    // tap here does; `MergeSemantics` folds it onto `InkWell`'s own inner
    // node, the one that actually carries the tap action, rather than
    // leaving it on a separate parent node.
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        label: object.name,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: ModelerMetrics.row,
            child: Row(
              children: <Widget>[
                Icon(
                  switch (object.geometry) {
                    ParametricGeometry() => Icons.category_outlined,
                    EditedGeometry() => Icons.hexagon_outlined,
                    ImportedGeometry() => Icons.download_outlined,
                  },
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      object.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                        fontWeight: selected
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A label and a value, on one row of the height the design names.
class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: ModelerMetrics.row,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The keyboard, over the whole shell.
///
/// **`Shortcuts` and `Actions` rather than a `RawKeyboardListener`**, because
/// this has to lose to a text field: a person typing 1.5 into a number field is
/// not asking for vertex level, and the focus system is what already knows the
/// difference. The tools come from the same table the rail reads, so a key
/// that arms nothing is a key nobody wrote down twice.
class _Keys extends StatelessWidget {
  const _Keys({
    required this.onKey,
    required this.onUndo,
    required this.onRedo,
    required this.onExport,
    required this.onTool,
    required this.onLevel,
    required this.onSelectAll,
    required this.onSelectNone,
    required this.onInvertSelection,
    required this.onShortcutHelp,
    required this.tools,
    required this.child,
  });

  /// A key that a transform in progress may want. Answers whether it took it,
  /// so the shortcuts below only see the ones it did not.
  final bool Function(LogicalKeyboardKey key, String? character) onKey;

  final VoidCallback onUndo;
  final VoidCallback onRedo;

  /// ⌘E. Bound to the container rather than to a menu, because it is the
  /// export a person repeats: the one that goes back into the game.
  final VoidCallback onExport;
  final ValueChanged<String> onTool;
  final ValueChanged<MeshSubmode> onLevel;
  final VoidCallback onSelectAll;
  final VoidCallback onSelectNone;
  final VoidCallback onInvertSelection;

  /// `?`. `ui-32n`'s own way in, beside the Help button in the top bar.
  final VoidCallback onShortcutHelp;
  final List<ModelerTool> tools;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Meta on a Mac and control everywhere else, which is what people's hands
    // already know. `Platform` is not reachable on the web, so this asks the
    // framework rather than the operating system.
    final bool apple =
        Theme.of(context).platform == TargetPlatform.macOS ||
        Theme.of(context).platform == TargetPlatform.iOS;
    final undo = apple
        ? const SingleActivator(LogicalKeyboardKey.keyZ, meta: true)
        : const SingleActivator(LogicalKeyboardKey.keyZ, control: true);
    final redo = apple
        ? const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          )
        : const SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: true,
            shift: true,
          );
    final export = apple
        ? const SingleActivator(LogicalKeyboardKey.keyE, meta: true)
        : const SingleActivator(LogicalKeyboardKey.keyE, control: true);
    // **A `Focus` with an `onKeyEvent` outside the shortcuts, because a
    // transform in progress has to see keys before they mean what they usually
    // mean.** `X` arms nothing while a move is going on — it constrains the
    // move — and `5` is a number rather than whatever `5` will one day be.
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        return onKey(event.logicalKey, event.character)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          undo: onUndo,
          redo: onRedo,
          export: onExport,
          for (final MeshSubmode level in MeshSubmode.values)
            SingleActivator(level.shortcut): _typingSafe(() => onLevel(level)),
          for (final ModelerTool tool in tools)
            SingleActivator(tool.shortcut): _typingSafe(() => onTool(tool.id)),
          for (final MapEntry<ShortcutActivator, VoidCallback> entry
              in selectionKeyBindings(
                tools: tools,
                onSelectAll: onSelectAll,
                onSelectNone: onSelectNone,
                onInvertSelection: onInvertSelection,
              ).entries)
            entry.key: _typingSafe(entry.value),
          const SingleActivator(LogicalKeyboardKey.slash, shift: true):
              _typingSafe(onShortcutHelp),
        },
        child: child,
      ),
    );
  }

  /// [action], unless a text field currently holds the keyboard focus.
  ///
  /// **`ui-12`'s own "фокус в `NumberField` перехватывает."** A bare letter or
  /// digit reaches this widget's own `CallbackShortcuts` whether or not a
  /// `TextField` further down the tree is focused — Flutter delivers the
  /// character to the field through the text-input channel, a path separate
  /// from the raw key event this binding sees, so nothing here stops a
  /// keystroke from doing both at once unless it is told to. Checked against
  /// the currently focused element's own ancestry rather than one field's
  /// `FocusNode`, since any `NumberField` anywhere in the panel needs the
  /// same protection, not just one.
  static VoidCallback _typingSafe(VoidCallback action) => () {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context != null &&
        context.findAncestorWidgetOfExactType<EditableText>() != null) {
      return;
    }
    action();
  };
}
