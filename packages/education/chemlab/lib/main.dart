/// A virtual chemistry bench.
///
///     flutter run -d chrome
///     flutter run -d macos
///
/// Glass turned from profiles, labels typeset in TeX and wrapped on, and a
/// slider that pours. Drag to turn round the bench, scroll to come closer,
/// pick a vessel and move the slider to fill or empty it.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'chemlab.dart';

void main() => runApp(const ChemLabApp());

class ChemLabApp extends StatelessWidget {
  const ChemLabApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chemistry bench',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2F6FD6),
        brightness: Brightness.dark,
      ),
    ),
    home: const BenchScreen(),
  );
}

class BenchScreen extends StatefulWidget {
  const BenchScreen({super.key});

  @override
  State<BenchScreen> createState() => _BenchScreenState();
}

class _BenchScreenState extends State<BenchScreen> {
  final CameraNode _camera = CameraNode(name: 'eye');
  late final RenderView _view = RenderView(
    camera: _camera,
    clearColor: Vector4(0.1, 0.11, 0.14, 1.0),
  );
  late final OrbitController _orbit = OrbitController(
    _camera,
    target: Vector3(0.1, 0.34, 0),
    distance: 2.7,
    yaw: 0.0,
    pitch: 0.2,
  );

  ({Renderer renderer, Bench bench})? _ready;
  Object? _error;
  int _selected = 1;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final device = await openDevice(width: 1280, height: 720);
      final renderer = Renderer.create(device: device);
      final bench = Bench(device)..retire = renderer.releaseMeshAfterFrame;
      bench.scene.add(_camera);
      if (!mounted) return;
      setState(() => _ready = (renderer: renderer, bench: bench));
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF14161A),
    body: switch ((_error, _ready)) {
      (final Object error, _) => DidNotStart(
        error,
        background: const Color(0xFF14161A),
        foreground: const Color(0xFFFF8A80),
      ),
      (_, null) => const Center(child: CircularProgressIndicator()),
      (_, (:final renderer, :final bench)?) => Stack(
        children: [
          // The labels, drawn out of sight and put on as they arrive; until
          // then the paper is blank.
          Positioned(
            left: 0,
            top: 0,
            width: 1,
            height: 1,
            child: LabelPrinter(
              solutions: [
                for (final v in bench.vessels)
                  if (v.solution != null) v.solution!,
              ],
              // setState, because SceneSurface draws when its widget
              // changes: a label put on between frames is not seen until
              // the next one.
              onPrinted: (i, image) => setState(
                () => bench.dress(
                  bench.vessels.where((v) => v.solution != null).elementAt(i),
                  image,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Listener(
              // In setState: SceneSurface draws in build, so a camera moved
              // without a rebuild is not drawn until something else is.
              onPointerMove: (PointerMoveEvent event) =>
                  setState(() => _orbit.rotate(event.delta.dx, event.delta.dy)),
              onPointerSignal: (PointerSignalEvent event) {
                if (event is PointerScrollEvent) {
                  setState(
                    () => _orbit.zoom(
                      event.scrollDelta.dy > 0.0 ? 1.1 : 1.0 / 1.1,
                    ),
                  );
                }
              },
              child: SceneSurface(
                renderer: renderer,
                scene: bench.scene,
                view: _view,
                settings: () => RenderSettings(sky: labSky),
                onBeforeFrame: () => _orbit.syncProjectionDepth(_camera),
                presentFrame: presentFrame,
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _Controls(
              bench: bench,
              selected: _selected,
              onSelect: (i) => setState(() => _selected = i),
              onPour: (level) =>
                  setState(() => bench.pour(bench.vessels[_selected], level)),
            ),
          ),
        ],
      ),
    },
  );
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.bench,
    required this.selected,
    required this.onSelect,
    required this.onPour,
  });

  final Bench bench;
  final int selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<double> onPour;

  @override
  Widget build(BuildContext context) {
    final vessel = bench.vessels[selected];
    return Card(
      color: const Color(0xE61C1F26),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // One row that scrolls rather than wraps, so the panel stays
            // two lines high in a small frame and the bench stays in view.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < bench.vessels.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Text(bench.vessels[i].name),
                        selected: i == selected,
                        avatar: CircleAvatar(
                          backgroundColor: bench.vessels[i].colour,
                        ),
                        onSelected: (_) => onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                const Text('Pour'),
                Expanded(
                  child: Slider(
                    value: vessel.level,
                    min: vessel.lowest,
                    max: vessel.highest,
                    onChanged: onPour,
                  ),
                ),
                Text(
                  'Drag to turn, scroll to zoom',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
