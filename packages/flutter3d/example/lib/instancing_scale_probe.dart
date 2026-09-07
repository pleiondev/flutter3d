/// How many instanced units a frame can carry, measured on a live GPU.
///
/// **The drawing half of a question whose other half is already answered.** The
/// strategy genre's first phase asked what a crowd costs, and the simulation
/// side came back cheap: ten thousand agents descending a flow field, shoving
/// each other apart through a proximity grid and writing their matrices cost
/// under a millisecond a step — six per cent of a frame at sixty. That
/// measurement was made in plain Dart with nothing drawn, and it says nothing
/// at all about the half that draws.
///
/// This asks that half. One `InstancedMeshNode` holds the crowd, every
/// instance's transform is rewritten every frame — which is the honest case,
/// because units that stand still would let the engine skip the upload the
/// real game cannot skip — and the probe walks up a ladder of counts, holding
/// each for a fixed number of frames and reporting what arrived.
///
/// **Frame interval rather than the cost of `render`.** `Renderer.render`
/// returns once the frame is encoded, and the GPU is still working when it
/// does, so timing that call measures encoding and calls it drawing. What a
/// player feels is how fast frames actually arrive, and that is what the ladder
/// reports; the encode cost is printed beside it because the difference between
/// the two is the interesting part — one is a CPU bill this repository can pay
/// down, the other is the device saying no.
///
/// Nothing here is the strategy genre, and nothing in the engine calls this. It
/// is an instrument, in the example beside `surface_probe.dart` and
/// `float_readback_probe.dart`, for the same reason they are: a measurement is
/// not a feature, and the numbers belong in a plan rather than in a package.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_backend/flutter3d_backend.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// One rung of the ladder: how many units, and what the frames did.
final class InstancingScaleRung {
  /// Records a rung.
  const InstancingScaleRung({
    required this.units,
    required this.frameMicros,
    required this.encodeMicros,
  });

  /// How many instances were drawn.
  final int units;

  /// Mean interval between finished frames, in microseconds.
  final double frameMicros;

  /// Mean cost of `Renderer.render` itself — encoding, not drawing.
  final double encodeMicros;

  /// Frames a second, as the interval implies.
  double get fps => 1e6 / frameMicros;
}

/// Everything the ladder found, ready to print.
final class InstancingScaleReport {
  /// Builds a report over [rungs].
  InstancingScaleReport(this.rungs);

  /// Each count that was measured, in the order measured.
  final List<InstancingScaleRung> rungs;

  /// The report as lines.
  List<String> get lines => <String>[
    'instancing scale probe',
    '',
    '   units    frame us     fps    encode us',
    for (final InstancingScaleRung r in rungs) _row(r),
  ];
}

String _row(InstancingScaleRung r) =>
    r.units.toString().padLeft(8) +
    r.frameMicros.toStringAsFixed(0).padLeft(12) +
    r.fps.toStringAsFixed(1).padLeft(8) +
    r.encodeMicros.toStringAsFixed(0).padLeft(13);

/// Draws a growing crowd and reports what each size cost.
class InstancingScaleProbe extends StatefulWidget {
  /// Builds the probe.
  const InstancingScaleProbe({required this.onDone, super.key});

  /// Told once, with every rung measured.
  final void Function(InstancingScaleReport report) onDone;

  @override
  State<InstancingScaleProbe> createState() => _InstancingScaleProbeState();
}

class _InstancingScaleProbeState extends State<InstancingScaleProbe> {
  /// The ladder. Stops well above the ten thousand the simulation half carried,
  /// so that the drawing half is given every chance to be the cheaper of the
  /// two before it is called the ceiling.
  static const List<int> _ladder = <int>[
    2000,
    20000,
    50000,
    100000,
    200000,
    400000,
  ];

  /// Frames held at each rung. The first few after a change are thrown away:
  /// a pipeline is compiled once and a buffer grows once, and both land in the
  /// frame that follows the change rather than in the ones being measured.
  static const int _warmup = 20;
  static const int _measured = 90;

  Renderer? _renderer;
  late final Scene _scene;
  late final RenderView _view;
  late final InstancedMeshNode _crowd;

  final List<InstancingScaleRung> _rungs = <InstancingScaleRung>[];
  final vm.Matrix4 _transform = vm.Matrix4.identity();
  int _rung = 0;
  int _frame = 0;
  int _lastFrameMicros = 0;
  int _intervalTotal = 0;
  int _encodeTotal = 0;
  double _phase = 0.0;
  final Stopwatch _clock = Stopwatch()..start();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final GraphicsDevice device = await openDevice(width: 1280, height: 720);
    if (!mounted) return device.dispose();

    _scene = Scene(name: 'crowd');

    // A cuboid rather than a sphere: a unit in a strategy is a handful of
    // triangles, and measuring the crowd with a sphere would measure the
    // sphere.
    _crowd = InstancedMeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: vm.Vector3(0.6, 1.2, 0.6)).build(),
      ),
      Material(
        lighting: LightingModel.pbr,
        baseColor: vm.Vector4(0.72, 0.68, 0.6, 1.0),
        roughness: 0.6,
      ),
      capacity: _ladder.last,
      name: 'crowd',
    );
    for (var i = 0; i < _ladder.last; i++) {
      _crowd.addInstance(vm.Matrix4.identity());
    }
    _crowd.count = _ladder.first;
    _scene.add(_crowd);

    _scene.add(
      LightNode(
        type: LightType.directional,
        color: vm.Vector3(1.0, 0.97, 0.9),
        intensity: 3.0,
        name: 'sun',
      )..lookAt(vm.Vector3(0.3, -1.0, 0.4)),
    );

    // High and looking down, the way a strategy looks at its map, so the crowd
    // is on screen rather than behind the camera.
    final camera = _scene.add(CameraNode(name: 'camera'))
      ..setPosition(0.0, 90.0, 90.0)
      ..lookAt(vm.Vector3.zero());
    _view = RenderView(camera: camera);

    setState(() => _renderer = Renderer.create(device: device));
  }

  /// Moves every instance, because a crowd that stands still is not the case.
  void _stir(int count) {
    _phase += 0.016;
    for (var i = 0; i < count; i++) {
      final row = i ~/ 100;
      final col = i % 100;
      final drift = 0.5 * (i.isEven ? 1.0 : -1.0);
      _transform.setIdentity();
      _transform.setTranslationRaw(
        (col - 50) * 1.1 + drift * _phase % 2.0,
        0.6,
        (row - 50) * 1.1,
      );
      _crowd.setTransform(i, _transform);
    }
  }

  void _tick(int encodeMicros) {
    final int now = _clock.elapsedMicroseconds;
    final int interval = now - _lastFrameMicros;
    _lastFrameMicros = now;
    _frame++;

    if (_frame > _warmup) {
      _intervalTotal += interval;
      _encodeTotal += encodeMicros;
    }
    if (_frame < _warmup + _measured) return;

    _rungs.add(
      InstancingScaleRung(
        units: _ladder[_rung],
        frameMicros: _intervalTotal / _measured,
        encodeMicros: _encodeTotal / _measured,
      ),
    );
    _frame = 0;
    _intervalTotal = 0;
    _encodeTotal = 0;
    _rung++;

    if (_rung >= _ladder.length) {
      _done = true;
      final report = InstancingScaleReport(_rungs);
      // Out of the build that is still running: the rung finishes inside
      // `build`, and telling anybody there is a `setState` during a build.
      scheduleMicrotask(() => widget.onDone(report));
      return;
    }
    _crowd.count = _ladder[_rung];
  }

  @override
  void dispose() {
    final Renderer? renderer = _renderer;
    if (renderer != null) {
      renderer.dispose();
      renderer.device.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Renderer? renderer = _renderer;
    if (renderer == null || _done) {
      return const ColoredBox(color: Color(0xFF101014));
    }

    // Repaint for ever: the ladder needs frames, and nothing else here asks
    // for them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_done) setState(() {});
    });

    final double dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _stir(_crowd.count);
        final Stopwatch encode = Stopwatch()..start();
        final frame = renderer.render(
          width: (constraints.maxWidth * dpr).round().clamp(1, 8192),
          height: (constraints.maxHeight * dpr).round().clamp(1, 8192),
          scene: _scene,
          views: <RenderView>[_view],
          settings: const RenderSettings(),
        );
        encode.stop();
        _tick(encode.elapsedMicroseconds);
        return renderer.device.present(frame.frame);
      },
    );
  }
}
