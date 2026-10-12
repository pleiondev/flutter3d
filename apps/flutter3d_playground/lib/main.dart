/// The playground: a level or a prefab document in an editor on one side,
/// drawn on the other as it is typed, and what is wrong with it said under
/// the text.
///
///     flutter run -d chrome
///
/// **The site's page is this application's web build** (`site/tool/demos.sh
/// playground`), so what a visitor sees is the engine's web backend drawing
/// the document: WebGL2, or WebGPU where the browser has it. On a desktop it
/// is the same widget on Impeller.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show Level;

import 'src/reading.dart';
import 'src/samples.dart';
import 'src/scene.dart';

export 'src/reading.dart';
export 'src/samples.dart';
export 'src/scene.dart';

void main() => runApp(const PlaygroundApp());

class PlaygroundApp extends StatelessWidget {
  const PlaygroundApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'flutter3d playground',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4FC3F7),
        brightness: Brightness.dark,
      ),
    ),
    home: const Playground(),
  );
}

class Playground extends StatefulWidget {
  const Playground({super.key, this.document = sampleLevel});

  /// What the editor opens on.
  final String document;

  @override
  State<Playground> createState() => PlaygroundState();
}

/// Public so a test can read what the playground made of its text.
class PlaygroundState extends State<Playground> {
  late final TextEditingController text = TextEditingController(
    text: widget.document,
  );

  final CameraNode _camera = CameraNode(name: 'eye');
  late final OrbitController _orbit = OrbitController(
    _camera,
    distance: 16.0,
    yaw: 0.5,
    pitch: 0.55,
    minDistance: 1.0,
    maxDistance: 200.0,
  );

  Flutter3dEngine? _engine;
  Timer? _typing;

  /// The last reading of the text.
  Reading reading = (level: null, problems: const <Problem>[]);

  /// The level being drawn: the last one that read, kept on screen while
  /// the text in the editor does not.
  Level? drawn;

  /// Whether the camera has been placed over a level yet.
  bool _framed = false;

  double _pinchFrom = 1.0;

  @override
  void initState() {
    super.initState();
    reading = readDocument(text.text);
  }

  @override
  void dispose() {
    _typing?.cancel();
    text.dispose();
    super.dispose();
  }

  void _edited(String _) {
    _typing?.cancel();
    // A quarter of a second after the last key: a scene a keystroke is a
    // rebuild of every mesh for text that is usually half a word.
    _typing = Timer(const Duration(milliseconds: 250), _read);
  }

  void _load(String document) {
    text.text = document;
    _framed = false;
    _read();
  }

  void _read() {
    setState(() => reading = readDocument(text.text));
    _draw();
  }

  /// Draws the last reading's level, when it has one and the view has a
  /// device to draw it on. A document that does not read leaves the last
  /// one that did on screen.
  void _draw() {
    final engine = _engine;
    final level = reading.level;
    if (engine == null || level == null) return;
    final Scene scene;
    try {
      scene = playgroundScene(level, engine.device);
    } on Object catch (error) {
      setState(
        () => reading = (
          level: null,
          problems: <Problem>[...reading.problems, Problem('$error')],
        ),
      );
      return;
    }
    final old = engine.scene;
    engine.scene = scene;
    // The old scene's meshes go back to the device once no frame in flight
    // can still read them; the marker is one mesh under many nodes.
    for (final mesh in <DeviceMesh>{
      for (final node in old.meshes)
        if (node.mesh case final DeviceMesh mesh) mesh,
    }) {
      engine.renderer.releaseMeshAfterFrame(mesh);
    }
    if (!_framed) {
      _framed = true;
      final bounds = scene.computeBounds();
      if (bounds.min.x <= bounds.max.x) _orbit.frameBounds(bounds);
    }
    setState(() => drawn = level);
  }

  void _opened(Flutter3dEngine engine) {
    _engine = engine;
    engine.view.clearColor = LinearColor.fromSrgb(0.07, 0.08, 0.1, 1.0);
    _draw();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final wide = box.maxWidth >= 760.0;
        final view = _view();
        final editor = _editor(context);
        return wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(width: box.maxWidth * 0.42, child: editor),
                  Expanded(child: view),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(height: box.maxHeight * 0.45, child: view),
                  Expanded(child: editor),
                ],
              );
      },
    ),
  );

  Widget _view() => Listener(
    onPointerSignal: (PointerSignalEvent event) {
      if (event is PointerScrollEvent) {
        _orbit.zoom(event.scrollDelta.dy > 0.0 ? 1.1 : 1.0 / 1.1);
      }
    },
    child: GestureDetector(
      onScaleStart: (ScaleStartDetails details) => _pinchFrom = _orbit.distance,
      onScaleUpdate: (ScaleUpdateDetails details) {
        _orbit.rotate(details.focalPointDelta.dx, details.focalPointDelta.dy);
        if (details.pointerCount > 1) {
          _orbit.zoom(_pinchFrom / details.scale / _orbit.distance);
        }
      },
      child: Flutter3dView(
        camera: _camera,
        onCreated: _opened,
        onBeforeFrame: (_, _) => _orbit.syncProjectionDepth(_camera),
        view: ViewSettings(
          placeholder: const ColoredBox(
            color: Color(0xFF121418),
            child: Center(child: CircularProgressIndicator()),
          ),
          failure: (Object error) => DidNotStart(
            error,
            background: const Color(0xFF121418),
            foreground: const Color(0xFFFF8A80),
          ),
        ),
      ),
    ),
  );

  Widget _editor(BuildContext context) {
    final theme = Theme.of(context);
    final problems = reading.problems;
    final level = drawn;
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 0.0),
            child: Wrap(
              spacing: 8.0,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text('Open', style: theme.textTheme.labelLarge),
                ActionChip(
                  label: const Text('a level'),
                  onPressed: () => _load(sampleLevel),
                ),
                ActionChip(
                  label: const Text('a prefab'),
                  onPressed: () => _load(samplePrefab),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                key: const ValueKey<String>('document'),
                controller: text,
                onChanged: _edited,
                expands: true,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'a level or a prefab document, as JSON',
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 12.0),
            child: Column(
              key: const ValueKey<String>('problems'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final problem in problems)
                  Text(
                    '${problem.isError ? 'error' : 'warning'}: $problem',
                    style: TextStyle(
                      color: problem.isError
                          ? theme.colorScheme.error
                          : theme.colorScheme.tertiary,
                    ),
                  ),
                if (level != null && !problems.any((p) => p.isError))
                  Text(
                    'drawn: ${level.brushes.length} brushes, '
                    '${level.lights.length} lights, '
                    '${level.entities.length} entities',
                    style: theme.textTheme.bodySmall,
                  ),
                if (problems.any((p) => p.isError) && level != null)
                  Text(
                    'still drawing the last document that read',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
