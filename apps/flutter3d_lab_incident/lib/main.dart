/// `ls-i-02`: `wg-02`'s own operator-panel demo, brought to a full
/// scenario — a recorded incident (`IncidentReplayController`, over a real
/// `DataSourceTrace`) an engineer steps through by name rather than a
/// frame-accurate scrubber, reading exactly what the sensor showed at each
/// named moment on the same panel `wg-02` already proved.
///
/// **Its own application, not a mode of `flutter3d_template_app`**, the same
/// reasoning `flutter3d_lab_twin`'s own `main.dart` already gives for
/// `ls-i-00`: the incident's own moments are this scenario's feature, not
/// something every new project starting from the seed needs baked in.
///
///     flutter run -d chrome
///     flutter run -d chrome --dart-define=FLUTTER_WEB_USE_SKIA=true
///
/// `?moment=N` opens straight at [spindleOverheatMoments]'s own Nth entry —
/// `ls-i-02`'s own "инженер открывает записанный сбой по ссылке".
library;

import 'dart:async';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/incident_panel.dart';
import 'src/incident_scenario.dart';

void main() {
  runApp(const IncidentReplayApp());
}

class IncidentReplayApp extends StatelessWidget {
  const IncidentReplayApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'ls-i-02: incident replay',
    debugShowCheckedModeBanner: false,
    home: IncidentScreen(),
  );
}

class IncidentScreen extends StatefulWidget {
  const IncidentScreen({super.key});

  @override
  State<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends State<IncidentScreen>
    with SingleTickerProviderStateMixin {
  static Vector3 get _machineAt => Vector3(0.0, 0.5, 0.0);

  /// Built once, from the closed-form curve — a recorded incident is read
  /// back the same way every time it is opened, the same determinism
  /// [recordSpindleOverheatIncident]'s own doc comment gives the reason for.
  late final IncidentReplayController _incident = IncidentReplayController(
    trace: recordSpindleOverheatIncident(),
    moments: spindleOverheatMoments,
    bindingPath: spindleTempBindingPath,
  );

  Renderer? _renderer;
  Object? _initError;
  late Scene _scene;
  late CameraNode _camera;
  late WidgetSurface _panel;
  Ticker? _ticker;

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
    final camera = CameraNode(name: 'eye')
      ..setPositionFrom(Vector3(0.0, 1.6, -4.2))
      ..lookAt(_machineAt);
    scene.add(camera);

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

    // Same fix `flutter3d_lab_twin`'s own `main.dart` already documents in
    // full: `WidgetSurface` content renders rotated a half turn from what
    // its geometry says, root cause open, worked around here the same way.
    final panel = WidgetSurface(
      device: device,
      width: 1.6,
      height: 1.2,
      name: 'operator-panel',
      child: Transform.flip(
        flipX: true,
        flipY: true,
        child: IncidentPanel(controller: _incident),
      ),
    )..setPosition(Vector3(1.6, 1.7, -1.4));
    scene.add(panel.node);

    _scene = scene;
    _camera = camera;
    _panel = panel;

    final moment = int.tryParse(Uri.base.queryParameters['moment'] ?? '');
    if (moment != null) _incident.jumpTo(moment);

    _ticker = createTicker((_) => unawaited(_panel.tick()))..start();
    if (mounted) setState(() => _renderer = Renderer.create(device: device));
  }

  void _go(void Function() move) => setState(move);

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
    return Scaffold(
      backgroundColor: const Color(0xFF14161A),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          SceneSurface(
            renderer: renderer,
            scene: _scene,
            view: RenderView(camera: _camera),
            settings: () => const RenderSettings(),
            onBeforeFrame: () {},
            // Required since the package merge: what hands a finished frame
            // to Flutter is the backend's own, reached through the same
            // barrel `openDevice` is.
            presentFrame: presentFrame,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24.0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  tooltip: 'Previous moment',
                  onPressed: _incident.isFirst
                      ? null
                      : () => _go(_incident.previous),
                ),
                const SizedBox(width: 24.0),
                IconButton(
                  icon: const Icon(Icons.arrow_forward, color: Colors.white),
                  tooltip: 'Next moment',
                  onPressed: _incident.isLast
                      ? null
                      : () => _go(_incident.next),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
