/// A live look at `edu-05`'s own mechanism, which until now existed only
/// under a test on a toy class (`run_timeline_data_source_test.dart`): a
/// real [SamplerDataSource] read every tick, a real `WidgetSurface` showing
/// it, and a real "what if" branch of the resulting [DataSourceTrace] —
/// `doc/lesson-scenarios-plan.md`'s `ls-i-00`.
///
/// **Its own application, not a mode of `flutter3d_template_app`.** `tpl-04`'s
/// own `twin.json` already proves the *format* half of this (an
/// `edu_data_source`/`edu_step.bindings` pair opens and resolves through the
/// generic level scaffold) — this app is the *scenario* half a generic
/// template should not carry: the what-if branch is `ls-i-00`'s own feature,
/// not something every new project starting from the seed needs baked in.
///
///     flutter run -d chrome
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_stereo/flutter3d_stereo.dart' as stereo;
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/twin_dashboard_panel.dart';

void main() {
  runApp(const DeviceTwinDemoApp());
}

class DeviceTwinDemoApp extends StatelessWidget {
  const DeviceTwinDemoApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'ls-i-00: device twin',
    debugShowCheckedModeBanner: false,
    home: DeviceTwinScreen(),
  );
}

class DeviceTwinScreen extends StatefulWidget {
  const DeviceTwinScreen({super.key});

  @override
  State<DeviceTwinScreen> createState() => _DeviceTwinScreenState();
}

class _DeviceTwinScreenState extends State<DeviceTwinScreen>
    with SingleTickerProviderStateMixin {
  static Vector3 get _machineAt => Vector3(0.0, 0.5, 0.0);

  /// The one twin this demo shows — `edu-00` §9's `kind: "sampler"`, the
  /// deterministic source that needs no broker: a sine sweep, the same shape
  /// `flutter3d_template_app`'s own `twin.json` reads for its dashboard.
  final DataSourceRegistry _dataSources = DataSourceRegistry(
    <String, EduDataSource>{
      'spindle-temp': SamplerDataSource(
        (step) => <String, Object?>{
          'value': 60.0 + 15.0 * math.sin(step * 0.05),
        },
      ),
    },
  );

  late final TwinWhatIfController _twin = TwinWhatIfController(
    dataSources: _dataSources,
    sourceName: 'spindle-temp',
    bindingPath: 'value',
  );

  final Raycaster _raycaster = Raycaster();

  Renderer? _renderer;
  Object? _initError;
  late Scene _scene;
  late WidgetSurface _panel;
  Ticker? _ticker;

  /// The flat screen's own stage, or the `ls-x-03` one — never both, the
  /// same "exactly one of the two" shape
  /// `apps/flutter3d_lesson_viewer/lib/main.dart`'s own `LessonReady`
  /// already carries for `ls-x-00`. `?stereo=1` in this app's own URL asks
  /// for the second, the same door that one answers.
  CameraNode? _camera;
  stereo.StereoRig? _rig;
  Duration _lastElapsed = Duration.zero;
  double _stepAccumulator = 0.0;
  int _step = 0;

  /// A fixed 20 Hz sampling rate — a temperature reading has no reason to
  /// resample at frame rate, and a rate independent of the display's own
  /// keeps the trace's step numbers meaningful across a slow frame.
  static const double _stepSeconds = 1.0 / 20.0;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final GraphicsDevice device;
    try {
      device = await openDevice(width: 1280, height: 720);
    } catch (error) {
      if (mounted) setState(() => _initError = error);
      return;
    }

    final scene = Scene();

    // `ls-x-03`: `?stereo=1` opens the same machine, the same live feed, in
    // `StereoViewer` instead of on the flat screen — never both stages built,
    // the same choice `?stereo=1` already makes for `ls-x-00` in
    // `apps/flutter3d_lesson_viewer`.
    final asStereo =
        Uri.base.queryParameters['stereo'] == '1' ||
        Uri.base.queryParameters['stereo'] == 'true';
    if (asStereo) {
      final rig = stereo.StereoRig()
        ..stage.setPositionFrom(Vector3(0.0, 1.6, -4.2))
        ..stage.lookAt(_machineAt);
      scene.add(rig.stage);
      _rig = rig;
    } else {
      final camera = CameraNode(name: 'eye')
        ..setPositionFrom(Vector3(0.0, 1.6, -4.2))
        ..lookAt(_machineAt);
      scene.add(camera);
      _camera = camera;
    }

    scene.add(
      LightNode(type: LightType.point, intensity: 8.0, name: 'sun')
        ..setPositionFrom(Vector3(1.0, 4.0, -3.0)),
    );

    final floor = MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(6.0, 0.1, 6.0)).build(),
      ),
      Material(
        lighting: LightingModel.pbr,
        baseColor: Vector4(0.32, 0.32, 0.34, 1.0),
        roughness: 0.9,
      ),
      name: 'floor',
    )..setPositionFrom(Vector3(0.0, -0.05, 0.0));
    scene.add(floor);

    final machine = MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(1.2, 1.0, 1.2)).build(),
      ),
      Material(
        lighting: LightingModel.pbr,
        baseColor: Vector4(0.3, 0.32, 0.36, 1.0),
        roughness: 0.55,
      ),
      name: 'machine',
    )..setPositionFrom(_machineAt);
    scene.add(machine);

    // Same fix `flutter3d_lab_pendulum`'s own `main.dart` already found and
    // documents in full: `WidgetSurface` content renders rotated a half turn
    // from what its geometry says, root cause open, worked around here the
    // same way.
    final panel = WidgetSurface(
      device: device,
      width: 1.6,
      height: 1.0,
      name: 'twin-panel',
      child: Transform.flip(
        flipX: true,
        flipY: true,
        child: TwinDashboardPanel(controller: _twin),
      ),
    )..setPosition(Vector3(1.6, 1.7, -1.4));
    scene.add(panel.node);

    _scene = scene;
    _panel = panel;

    _ticker = createTicker(_onTick)..start();
    if (mounted) setState(() => _renderer = Renderer.create(device: device));
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    // The first callback's `elapsed` is already nonzero (a ticker's clock
    // starts when the scheduler binding did, not when this one started), so
    // clamping is what stands in for "skip the first frame" without a bool
    // — the same guard `flutter3d_lab_pendulum`'s own `_onTick` uses.
    _stepAccumulator += dt.clamp(0.0, 0.05);
    while (_stepAccumulator >= _stepSeconds) {
      _stepAccumulator -= _stepSeconds;
      _twin.sampleAndRecord(_step);
      _step++;
    }
    unawaited(_panel.tick());
    if (mounted) setState(() {});
  }

  /// The same raycast `flutter3d_lab_pendulum`'s own `_tapPanel` and
  /// `flutter3d_template_app`'s own `_tapWidgetSurface` already prove.
  ///
  /// **Flat screen only.** `?stereo=1` has no `CameraNode` to raycast from —
  /// a single ray from a headset's own pointer is a real feature
  /// (`ls-x-02`'s own territory, HUD/input inside a helmet), not something
  /// this scenario's own acceptance line asks for: `ls-x-03` only promises
  /// the same what-if trace stays *visible* in stereo, not that it stays
  /// *tappable* from inside one.
  bool _tapPanel(Offset local) {
    final camera = _camera;
    if (camera == null) return false;
    final size = context.size;
    if (size == null || size.width <= 0.0 || size.height <= 0.0) return false;
    final hit = _raycaster
        .setFromScreen(
          camera,
          local.dx,
          local.dy,
          width: size.width,
          height: size.height,
        )
        .intersectScene(_scene);
    if (hit == null || hit.node != _panel.node) return false;
    final surfaceUv = _panel.uvAt(hit.point);
    if (surfaceUv == null) return false;

    final uv = Offset(surfaceUv.dx, 1.0 - surfaceUv.dy);

    const pointer = 9002;
    _panel.pipeline.announcePointer(pointer, added: true);
    _panel.pipeline.dispatchAtUv(
      uv,
      (local) => PointerDownEvent(pointer: pointer, position: local),
    );
    _panel.pipeline.dispatchAtUv(
      uv,
      (local) => PointerUpEvent(pointer: pointer, position: local),
    );
    _panel.pipeline.announcePointer(pointer, added: false);
    return true;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initError = _initError;
    if (initError != null) {
      return DidNotStart(
        initError,
        background: const Color(0xFF14161A),
        foreground: const Color(0xFFFF8A80),
      );
    }
    final renderer = _renderer;
    if (renderer == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF14161A),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_rig case final stereo.StereoRig rig) {
      return Scaffold(
        backgroundColor: const Color(0xFF14161A),
        body: stereo.StereoSurface(
          renderer: renderer,
          scene: _scene,
          rig: rig,
          settings: () => const RenderSettings().forStereo(),
          onBeforeFrame: () {},
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF14161A),
      body: Listener(
        onPointerDown: (PointerDownEvent event) =>
            _tapPanel(event.localPosition),
        child: SceneSurface(
          renderer: renderer,
          scene: _scene,
          view: RenderView(camera: _camera!),
          settings: () => const RenderSettings(),
          onBeforeFrame: () {},
        ),
      ),
    );
  }
}
