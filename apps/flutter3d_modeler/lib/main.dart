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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'src/backend.dart';
import 'src/churn_run.dart';
import 'src/display_modes.dart';
import 'src/element_picking.dart';
import 'src/files/project_files.dart';
import 'src/files/sandbox_probe.dart';
import 'src/ground_grid.dart';
import 'src/modeler_viewport.dart';
import 'src/object_picking.dart';
import 'src/orbit_run.dart';
import 'src/orientation_dial.dart';
import 'src/staging.dart';
import 'src/ui/shell.dart';
import 'src/ui/theme.dart';
import 'src/ui/tools.dart';

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
sealed class ModelerScreenState {
  const ModelerScreenState();
}

/// Before the device is up.
final class ModelerOpening extends ModelerScreenState {
  const ModelerOpening();
}

/// A device, a renderer and a world.
final class ModelerReady extends ModelerScreenState {
  const ModelerReady(this.renderer, this.stage);
  final Renderer renderer;
  final ModelerStage stage;
}

/// Nothing to draw with, and the sentence saying why.
final class ModelerFailed extends ModelerScreenState {
  const ModelerFailed(this.said);
  final String said;
}

/// One mesh, as the document a writer takes.
///
/// **A local class rather than a shared one, and only until phase 1.** The
/// plan's `fmt-02` puts a `PlainModelDocument` in `flutter3d_formats`, where
/// the tests that build documents by hand can share it; today the only caller
/// is this button, and a type published for one caller is a type nobody can
/// change afterwards.
final class _OneMesh extends ModelDocument {
  _OneMesh(MeshData mesh)
    : surfaces = <ModelSurface>[ModelSurface(mesh: mesh, name: 'model')];

  @override
  final List<ModelSurface> surfaces;

  @override
  List<SurfaceMaterial> get materials => const <SurfaceMaterial>[];

  @override
  List<EncodedImage> get images => const <EncodedImage>[];

  @override
  List<String> get warnings => const <String>[];
}

/// A model whose bytes are already in memory.
///
/// Both halves of `ProjectFiles` hand over bytes rather than a path — a browser
/// has no path at all — and the decoders take an `AssetSource`, so this is the
/// adapter between them. Sibling files are refused rather than guessed: a
/// `.gltf` with an external `.bin` is a case `ui-16` handles by asking for both
/// files, and answering it wrongly here would look like a corrupt model.
final class _Bytes extends AssetSource {
  const _Bytes(this._name, this._bytes);

  final String _name;
  final Uint8List _bytes;

  @override
  String get key => 'memory:$_name';

  @override
  Future<Uint8List> read() async => _bytes;

  @override
  AssetUriResolver get resolveUri => (AssetRequest request) async {
    if (request.uri.startsWith('data:')) return decodeDataUri(request.uri);
    throw StateError(
      'this model refers to "${request.uri}", and only the file itself was '
      'opened',
    );
  };
}

class ModelerScreen extends StatefulWidget {
  const ModelerScreen({super.key});

  @override
  State<ModelerScreen> createState() => _ModelerScreenState();
}

class _ModelerScreenState extends State<ModelerScreen>
    with SingleTickerProviderStateMixin {
  ModelerScreenState _state = const ModelerOpening();

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
  String? _fileSaid;

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
  ModelerMode _mode = ModelerMode.object;
  MeshSubmode _submode = MeshSubmode.vertex;
  String? _tool = 'object.select';

  /// The document, and everything that has been done to it.
  ///
  /// **One history for both modes**, which is what replaced the mesh-only
  /// session: ⌘Z now takes back a rename, a move of an object and an extrusion
  /// with the same press, in the order they were made. Two stacks would have
  /// meant a person undoing a move and getting an extrusion back.
  ModelHistory _history = ModelHistory(_newProject());

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
  EditMesh? get _editMesh => switch (_history
      .project[_history.selection.activeObject ?? -1]
      ?.geometry) {
    EditedGeometry(:final mesh) => mesh,
    _ => null,
  };

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
  String? _opSaid;

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

  @override
  void initState() {
    super.initState();
    // A ticker rather than `setState` from a timer: the viewport draws from
    // whatever the camera is now, and the frame is what asks for the next one.
    _ticker = createTicker(_onTick)..start();
    _timings.start();
    unawaited(_open());
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
    super.dispose();
  }

  Future<void> _open() async {
    // What it costs to get to the first frame, which on the web is a different
    // number from what a frame costs afterwards — and the one a person waiting
    // at a white page is actually measuring.
    final opening = Stopwatch()..start();
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
          : ModelerStage.fromProject(device: device, project: _history.project);
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
        if (mounted) setState(() => _fileSaid = said);
        // The other half of the question needs the panel, and the panel needs
        // somebody to answer it: this opens it, and what comes back — the write
        // and whether a rename beside it would have worked — is printed the
        // same way. See `saveAs`.
        if (kSandboxPick) await _saveFile();
      }
      setState(() {
        _state = ModelerReady(renderer, stage);
        // With no run to wait for, the opening cost is the whole report.
        if (kOrbit <= 0) _report = 'opened in $_openedInMs ms';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _state = ModelerFailed('$error'));
    }
  }

  /// Opens a model the person chose, and puts it in front of the camera.
  ///
  /// The whole of `p0-08` on the web and the ordinary path everywhere else:
  /// bytes from a picker, `decodeModel` over them, upload, frame. Nothing here
  /// branches on the platform — `ProjectFiles` already did.
  Future<void> _openFile() async {
    final device = _device;
    if (device == null) return;
    setState(() => _fileSaid = 'choosing…');
    try {
      final picked = await openModel();
      if (picked == null) {
        if (mounted) setState(() => _fileSaid = 'nothing chosen');
        return;
      }
      final opening = Stopwatch()..start();
      final document = await decodeModel(
        ModelLoadRequest(source: _Bytes(picked.name, picked.bytes)),
      );
      final asset = await ModelAsset.fromDocument(
        document,
        device: device,
        name: picked.name,
      );
      if (!mounted) return;
      final stage = ModelerStage.build(device: device, asset: asset);
      stage.frameSubject();
      opening.stop();
      // The scene the old materials belonged to is going, and the selection
      // points at nodes that are no longer drawn.
      _surfaces.forget();
      setState(() {
        _history = ModelHistory(_newProject());
        _state = ModelerReady((_state as ModelerReady).renderer, stage);
        _fileSaid =
            '${picked.name}: ${document.surfaces.length} surfaces, '
            'opened in ${opening.elapsedMilliseconds} ms';
      });
    } catch (error) {
      if (mounted) setState(() => _fileSaid = 'could not open it: $error');
    }
  }

  /// Writes what is on screen as the engine's own container.
  ///
  /// On a desktop that is a file somebody chose; in a browser it is a
  /// download. The spike part is what follows the write: `p0-13n` asks whether
  /// the same directory would have taken a temporary file and a rename, and
  /// the answer goes on the screen beside the result.
  Future<void> _saveFile() async {
    final state = _state;
    if (state is! ModelerReady) return;
    final mesh = _meshOf(state.stage.subject);
    if (mesh == null) {
      setState(() => _fileSaid = 'nothing to save');
      return;
    }

    final bytes = F3dWriter(_OneMesh(mesh)).write();
    final result = await saveAs(bytes, suggestedName: 'model.f3d');

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
    if (mounted) setState(() => _fileSaid = said);
  }

  /// The element level the sub-mode names.
  static ElementLevel _levelOf(MeshSubmode submode) => switch (submode) {
    MeshSubmode.vertex => ElementLevel.vertex,
    MeshSubmode.edge => ElementLevel.edge,
    MeshSubmode.face => ElementLevel.face,
  };

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
      level: _levelOf(_submode),
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
      _opSaid = null;
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

    final look = state.stage.overlayView(viewportHeight);
    // At the middle of what is being moved, because that is the depth the drag
    // has to be measured at: a pixel is a different number of metres a metre
    // further away.
    final vm.Vector3 middle = _middleOfSelection();
    final double metres =
        look.pixel * (look.perspective ? (middle - look.eye).length : 1.0);
    final vm.Vector3 along =
        look.right * (delta.dx * metres) + look.up * (-delta.dy * metres);

    // **A transaction, opened on the first move of a drag and closed when the
    // pointer goes up.** Every frame of a drag is a command; the history
    // collapses them into one step, so ⌘Z takes back the drag rather than a
    // sixtieth of it.
    if (!_dragging) {
      _dragging = true;
      _history.beginTransaction();
    }

    final String? said = _history.selection.mode == SelectionMode.mesh
        ? _history.run(_meshDrag(tool, along, middle, delta))
        : _history.run(_objectDrag(tool, along, look, middle, delta));
    if (said != null) setState(() => _opSaid = said);
    _sync();
  }

  /// Whether a drag is in progress, so its commands land in one step.
  bool _dragging = false;

  void _endDrag() {
    if (!_dragging) return;
    _dragging = false;
    _history.endTransaction();
    setState(() {});
  }

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

  ModelCommand _meshDrag(
    String tool,
    vm.Vector3 along,
    vm.Vector3 middle,
    Offset delta,
  ) {
    final vm.Matrix4 by = switch (tool) {
      'mesh.move' => vm.Matrix4.translation(along),
      'mesh.rotate' => _about(
        middle,
        vm.Matrix4.compose(
          vm.Vector3.zero(),
          vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), delta.dx * 0.01),
          vm.Vector3.all(1),
        ),
      ),
      _ => _about(
        middle,
        vm.Matrix4.diagonal3(vm.Vector3.all(1 + delta.dx * 0.01)),
      ),
    };
    return TransformElements(by, what: _dragWord(tool));
  }

  ModelCommand _objectDrag(
    String tool,
    vm.Vector3 along,
    ({
      vm.Vector3 eye,
      vm.Vector3 right,
      vm.Vector3 up,
      double pixel,
      bool perspective,
    })
    look,
    vm.Vector3 middle,
    Offset delta,
  ) => switch (tool) {
    'object.move' => MoveBy(along),
    'object.rotate' => RotateBy(
      // About the axis the camera is looking down, so a horizontal drag turns
      // the model the way the hand went whatever angle it is being seen from.
      axis: (look.eye - middle).normalized(),
      radians: delta.dx * 0.01,
    ),
    _ => ScaleBy(1 + delta.dx * 0.01),
  };

  static String _dragWord(String tool) => tool.endsWith('rotate')
      ? 'turn'
      : (tool.endsWith('scale') ? 'scale' : 'move');

  /// [by] applied about [pivot], which is what a turn and a scale mean.
  static vm.Matrix4 _about(vm.Vector3 pivot, vm.Matrix4 by) {
    final vm.Matrix4 about = vm.Matrix4.translation(pivot);
    about.multiply(by);
    about.multiply(vm.Matrix4.translation(-pivot));
    return about;
  }

  /// Presses a rail button.
  void _ranTool(String id) {
    if (kDragTools.contains(id) || id.endsWith('.select')) {
      // Arming rather than acting: these wait for a pointer.
      setState(() => _tool = id);
      return;
    }
    final ModelCommand? command = _commandFor(id);
    if (command == null) {
      setState(() => _tool = id);
      return;
    }
    final said = _history.run(command);
    setState(() {
      _tool = id;
      _opSaid = said;
    });
    if (said == null) _sync();
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
    'mesh.extrude' => Extrude(_stepOf()),
    'mesh.loopCut' => const LoopCut(),
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

  /// Brings the scene to the project.
  void _sync() {
    final state = _state;
    if (state is! ModelerReady) return;
    state.stage.sync?.apply(_history.project);
  }

  /// ⌘Z and ⇧⌘Z.
  void _undo() {
    final moved = _history.undo();
    setState(() => _opSaid = moved ? null : 'nothing to undo');
    if (moved) _sync();
  }

  void _redo() {
    final moved = _history.redo();
    setState(() => _opSaid = moved ? null : 'nothing to redo');
    if (moved) _sync();
  }

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
      _opSaid = null;
    });
  }

  /// What the selection is, in the words the status line shows.
  String get _selectionSaid => _history.selection.says;

  /// The first mesh under [node], which is what a save writes.
  static MeshData? _meshOf(SceneNode node) {
    MeshData? found;
    node.traverse((SceneNode each) {
      if (found != null || each is! MeshNode) return;
      found = each.mesh.source;
    });
    return found;
  }

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
  Widget build(BuildContext context) => switch (_state) {
    ModelerOpening() => const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    ),
    ModelerFailed(:final said) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(said, textAlign: TextAlign.center),
        ),
      ),
    ),
    ModelerReady(:final renderer, :final stage) => _Keys(
      onUndo: _undo,
      onRedo: _redo,
      onTool: _ranTool,
      onLevel: (MeshSubmode submode) => setState(() {
        _submode = submode;
        // Through `convertedTo`, so a person who picked a face and pressed 1
        // gets its corners rather than an empty viewport.
        final EditMesh? mesh = _editMesh;
        final was = _history.selection;
        _history.selection = mesh == null
            ? was.copyWith(level: _levelOf(submode))
            : was.copyWith(
                level: _levelOf(submode),
                elements: was.asMeshSelection
                    .convertedTo(mesh, _levelOf(submode))
                    .ids
                    .toList(),
              );
      }),
      tools: toolsFor(_mode),
      child: ModelerShell(
        mode: _mode,
        onMode: (ModelerMode mode) => setState(() {
          _mode = mode;
          // The armed tool belongs to the mode it came from, so a mode change
          // arms that mode's pointer rather than leaving a tool id from the old
          // one that nothing here would recognise.
          _tool = toolsFor(mode).isEmpty ? null : toolsFor(mode).first.id;
        }),
        submode: _submode,
        onSubmode: (MeshSubmode submode) => setState(() {
          _submode = submode;
          // Through `convertedTo`, so a person who picked a face and pressed 1
          // gets its corners rather than an empty viewport.
          final EditMesh? mesh = _editMesh;
          final was = _history.selection;
          _history.selection = mesh == null
              ? was.copyWith(level: _levelOf(submode))
              : was.copyWith(
                  level: _levelOf(submode),
                  elements: was.asMeshSelection
                      .convertedTo(mesh, _levelOf(submode))
                      .ids
                      .toList(),
                );
        }),
        activeTool: _tool,
        onTool: _ranTool,
        actions: <Widget>[
          TextButton(onPressed: _openFile, child: const Text('Open')),
          const SizedBox(width: 4),
          FilledButton.tonal(
            onPressed: _saveFile,
            child: const Text('Save as .f3d'),
          ),
        ],
        status: _StatusLine(
          said: _opSaid ?? _fileSaid ?? _selectionSaid,
          micros: _lastRenderMicros,
        ),
        properties: _Properties(
          stage: stage,
          project: _history.project,
          selection: _history.selection,
          onSelect: (int id) => setState(
            () => _history.selection = _history.selection.copyWith(
              mode: SelectionMode.object,
              objects: <int>[id],
            ),
          ),
          shading: _shading,
          onShading: (ShadingMode mode) => setState(() => _shading = mode),
          lens: _lens,
          onLens: (ViewLens lens) => setState(() => _lens = lens),
          onView: (StandardView view) => lookFrom(stage.orbit, view),
        ),
        viewport: Stack(
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
                onDragTool: _dragged,
                onDragDone: _endDrag,
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
        ),
      ),
    ),
  };
}

/// The line along the bottom: what just happened, and what the last frame cost.
///
/// The metrics `ui-10` asks for — the mode's own counts, and the first issue
/// from an export readiness — need a document to count and a readiness to ask,
/// so what is here is what the application actually knows.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.said, required this.micros});

  final String said;
  final int? micros;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            said,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
        if (micros case final int spent)
          Text(
            '${(spent / 1000).toStringAsFixed(1)} ms',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

/// The right-hand panel.
///
/// **Thin, and honest about why.** `ui-08` puts an object list, three-by-three
/// number fields and a modifier stack here, and every one of those edits a
/// `ModelProject` through a command — which is `doc-03` and `doc-05`, and is
/// the step this application is waiting on. What a panel can show today is what
/// the viewport knows: what is selected, how the surface is drawn, and where
/// the camera is standing. Those are real controls that belong here rather than
/// floating over the picture, which is where they were.
class _Properties extends StatelessWidget {
  const _Properties({
    required this.stage,
    required this.project,
    required this.selection,
    required this.onSelect,
    required this.shading,
    required this.onShading,
    required this.lens,
    required this.onLens,
    required this.onView,
  });

  final ModelerStage stage;
  final ModelProject project;
  final ProjectSelection selection;
  final ValueChanged<int> onSelect;
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
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      children: <Widget>[
        _Section('Display'),
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
        _Section('View'),
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
        _Section('Objects'),
        for (final ModelObject object in project.objects)
          _ObjectRow(
            object: object,
            selected: selection.objects.contains(object.id),
            onTap: () => onSelect(object.id),
          ),
        _Section('Selection'),
        _Row('What', selection.says),
        if (mesh != null) ...<Widget>[
          _Section('Mesh'),
          _Row('Vertices', '${mesh.vertexCount}'),
          _Row('Faces', '${mesh.faceCount}'),
        ],
        _Section('Budget'),
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
    return InkWell(
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
              child: Text(
                object.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A heading in the properties panel. `ui-08` calls this `section_label.dart`
/// and shares it between the two editors; it is four lines until then.
class _Section extends StatelessWidget {
  const _Section(this.said);

  final String said;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(
      said.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.6,
      ),
    ),
  );
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
    required this.onUndo,
    required this.onRedo,
    required this.onTool,
    required this.onLevel,
    required this.tools,
    required this.child,
  });

  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final ValueChanged<String> onTool;
  final ValueChanged<MeshSubmode> onLevel;
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
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        undo: onUndo,
        redo: onRedo,
        for (final MeshSubmode level in MeshSubmode.values)
          SingleActivator(level.shortcut): () => onLevel(level),
        for (final ModelerTool tool in tools)
          SingleActivator(tool.shortcut): () => onTool(tool.id),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
