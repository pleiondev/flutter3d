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
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_session/flutter3d_session.dart';

import 'src/backend.dart';
import 'src/churn_run.dart';
import 'src/files/project_files.dart';
import 'src/files/sandbox_probe.dart';
import 'src/modeler_viewport.dart';
import 'src/orbit_run.dart';
import 'src/staging.dart';

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
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      visualDensity: VisualDensity.compact,
    ),
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

      final stage = ModelerStage.build(
        device: device,
        asset: asset,
        stressTriangles: kStress,
        stressObjects: kStressObjects,
      );
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
      setState(() {
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0E1112),
    body: switch (_state) {
      ModelerOpening() => const Center(child: CircularProgressIndicator()),
      ModelerFailed(:final said) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(said, textAlign: TextAlign.center),
        ),
      ),
      ModelerReady(:final renderer, :final stage) => Stack(
        children: <Widget>[
          ModelerViewport(
            renderer: renderer,
            stage: stage,
            onFrame: () {},
            onRendered: (int micros) => _lastRenderMicros = micros,
          ),
          Positioned(
            right: 12,
            top: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    FilledButton.tonal(
                      onPressed: _openFile,
                      child: const Text('Open'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: _saveFile,
                      child: const Text('Save as .f3d'),
                    ),
                  ],
                ),
                if (_fileSaid case final String said)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xCC000000),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            said,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: Color(0xFFE6E9EA),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
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
                      color: Color(0xFFE6E9EA),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    },
  );
}
