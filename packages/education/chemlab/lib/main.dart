/// A virtual chemistry bench.
///
///     flutter run -d chrome
///     flutter run -d macos
///
/// Glass turned from profiles, labels typeset in TeX and wrapped on, and
/// liquid that keeps level and sloshes. Drag to turn round the bench, scroll
/// to come closer, pick a vessel and pour, tilt or tap it.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
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

class _BenchScreenState extends State<BenchScreen>
    with SingleTickerProviderStateMixin {
  final CameraNode _camera = CameraNode(name: 'eye');
  late final RenderView _view = RenderView(
    camera: _camera,
    clearColor: Vector4(0.1, 0.11, 0.14, 1.0),
  );
  // A bench is looked at from above and from not too far: the controller's
  // own limits let the camera go under the table and out of the room.
  late final OrbitController _orbit = OrbitController(
    _camera,
    // Life size: a bench of test tubes sixteen millimetres across.
    target: Vector3(0.01, 0.034, 0),
    distance: 0.27,
    yaw: 0.0,
    pitch: 0.2,
    minDistance: 0.06,
    maxDistance: 0.6,
  )..rotateSensitivity = 0.005;

  static const double _lowestPitch = 0.05;
  static const double _highestPitch = 1.35;

  void _turn(double dx, double dy) {
    _orbit.rotate(dx, dy);
    final pitch = _orbit.pitch.clamp(_lowestPitch, _highestPitch);
    if (pitch != _orbit.pitch) {
      _orbit
        ..pitch = pitch
        ..apply();
    }
  }

  ({Renderer renderer, Bench bench})? _ready;
  Object? _error;
  int _selected = 1;

  /// Runs while a liquid moves, and stops when every one is still.
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  void _tick(Duration elapsed) {
    final bench = _ready?.bench;
    // A frame late is a frame long: held to a thirtieth, so a stall does not
    // throw the liquid out of its glass.
    final seconds = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _last = elapsed;
    if (bench == null) return;
    final moving = bench.step(seconds);
    setState(() {});
    if (!moving) _ticker.stop();
  }

  /// The way the camera looks, which a vessel leans about so that it leans
  /// in the picture rather than towards the eye.
  Vector3 _lookingAlong() {
    final m = _camera.worldMatrix;
    return Vector3(-m.entry(0, 2), 0, -m.entry(2, 2));
  }

  /// Something has set a liquid moving: run the clock if it is not running.
  void _stir() {
    if (_ticker.isActive) return;
    _last = Duration.zero;
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final device = await openDevice(width: 1280, height: 720);
      final renderer = Renderer.create(device: device);
      final bench = Bench(device, photons: true)
        ..retire = renderer.releaseMeshAfterFrame
        ..retireTexture = renderer.releaseTextureAfterFrame;
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
                  setState(() => _turn(event.delta.dx, event.delta.dy)),
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
                settings: () => bench.settings,
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
              onPour: (level) {
                setState(() => bench.pour(bench.vessels[_selected], level));
                _stir();
              },
              onLean: (angle) {
                setState(
                  () => bench.lean(
                    bench.vessels[_selected],
                    angle,
                    across: _lookingAlong(),
                  ),
                );
                _stir();
              },
              onTap: () {
                bench.tap(bench.vessels[_selected]);
                _stir();
              },
              onShare: () {
                setState(
                  () => bench.share(
                    bench.vessels[_selected],
                    across: _lookingAlong(),
                  ),
                );
                _stir();
              },
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
    required this.onLean,
    required this.onTap,
    required this.onShare,
  });

  final Bench bench;
  final int selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<double> onPour;
  final ValueChanged<double> onLean;
  final VoidCallback onTap;

  /// Pours the picked vessel into the clean tube until both hold the same.
  final VoidCallback onShare;

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
                          backgroundColor: bench.colour(bench.vessels[i]),
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
                    // Held to the slider's range: a pour tips and empties
                    // the vessel past what the controls offer, and a slider
                    // given a value outside its range throws.
                    value: vessel.level.clamp(vessel.lowest, vessel.highest),
                    min: vessel.lowest,
                    max: vessel.highest,
                    onChanged: bench.busy ? null : onPour,
                  ),
                ),
                const Text('Tilt'),
                Expanded(
                  child: Slider(
                    // Where the hand is going, not where the glass is yet:
                    // it turns at a hand's pace, and a slider that followed
                    // it would pull back under the finger.
                    value: vessel.aimTilt.clamp(
                      -bench.maxLean(vessel),
                      bench.maxLean(vessel),
                    ),
                    min: -bench.maxLean(vessel),
                    max: bench.maxLean(vessel),
                    onChanged: bench.busy ? null : onLean,
                  ),
                ),
              ],
            ),
            // The buttons on a line of their own, which wraps: sharing one
            // with the sliders squeezed them to nothing in a narrow window.
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: const Text('Tap'),
                  onPressed: onTap,
                ),
                Tooltip(
                  message:
                      'Pour into the clean tube at the front until the two '
                      'hold the same',
                  child: ActionChip(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: const Text('Share with clean tube'),
                    onPressed: bench.canShare(vessel) ? onShare : null,
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
