/// A live look at `edu-04`'s own pieces, all of which existed only behind
/// tests until now: a real swinging [PendulumSimulation], a real
/// `WidgetSurface` carrying [PendulumLabPanel], a real tap routed through
/// [Raycaster] the same way `flutter3d_template_app`'s own
/// `_tapWidgetSurface` already proved for `tpl-04`.
///
/// Its own entrypoint, not a mode of the crypt's `main.dart`: nothing here
/// is a level, a genre or a save — it is a demonstration, run with
///
///     flutter run -d chrome -t lib/pendulum_lab_demo.dart
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_lab/flutter3d_lab.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/pendulum_lab_panel.dart';

void main() {
  runApp(const PendulumLabDemoApp());
}

class PendulumLabDemoApp extends StatelessWidget {
  const PendulumLabDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'edu-04: pendulum lab',
      debugShowCheckedModeBanner: false,
      home: PendulumLabScreen(),
    );
  }
}

class PendulumLabScreen extends StatefulWidget {
  const PendulumLabScreen({super.key});

  @override
  State<PendulumLabScreen> createState() => _PendulumLabScreenState();
}

class _PendulumLabScreenState extends State<PendulumLabScreen>
    with SingleTickerProviderStateMixin {
  static final Vector3 _pivot = Vector3(0.0, 2.0, 0.0);

  final PendulumSimulation _pendulum = PendulumSimulation(
    lengthMeters: 1.2,
    startAngle: 0.9,
  );
  final ValueNotifier<double> _length = ValueNotifier<double>(1.2);
  final Raycaster _raycaster = Raycaster();

  Renderer? _renderer;
  Object? _initError;
  late Scene _scene;
  late CameraNode _camera;
  late MeshNode _bob;
  late WidgetSurface _panel;
  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;

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
    // `-Z`, not `+Z`: `WidgetSurface.yaw`'s setter always applies yaw *before*
    // the fixed `pitch = -π/2` that stands the plane up
    // (`SceneNode.setRotationYawPitchRoll`'s own order), so a panel turned to
    // face `+Z` with `yaw = π` tips up already rotated a half-turn and
    // renders upside down — found live, not guessed: `edu-00` §7's
    // `view-caption` widget carries the identical `yaw: 3.1416` and would
    // have the same fault the day something actually draws it. Easier to
    // stand on the side the panel's default `yaw = 0.0` already faces than
    // to fight the order.
    final camera = CameraNode(name: 'eye')
      ..setPositionFrom(Vector3(0.0, 1.6, -4.2))
      ..lookAt(_pivot);
    scene.add(camera);

    scene.add(
      LightNode(type: LightType.point, intensity: 8.0, name: 'sun')
        ..setPositionFrom(Vector3(1.0, 4.0, -3.0)),
    );

    final pivotMesh = MeshNode(
      DeviceMesh.upload(device, const SphereShape(radius: 0.06).build()),
      Material(lighting: LightingModel.unlit, baseColor: Vector4(0.6, 0.62, 0.66, 1.0)),
      name: 'pivot',
    )..setPositionFrom(_pivot);
    scene.add(pivotMesh);

    final bob = MeshNode(
      DeviceMesh.upload(device, const SphereShape(radius: 0.16).build()),
      Material(lighting: LightingModel.pbr, baseColor: Vector4(0.86, 0.71, 0.32, 1.0), roughness: 0.4),
      name: 'bob',
    );
    scene.add(bob);

    // Left at its default `yaw = 0.0`: that already faces `-Z`, which is
    // where the camera stands (see the comment on `camera` above for why
    // turning the panel instead would render it upside down).
    final panel = WidgetSurface(
      device: device,
      width: 1.0,
      height: 0.7,
      name: 'pendulum-panel',
      child: PendulumLabPanel(
        lengthMeters: _length,
        onChangeLength: (value) {
          _pendulum.lengthMeters = value;
          _length.value = value;
        },
      ),
    )..setPosition(Vector3(1.3, 1.8, -0.4));
    scene.add(panel.node);

    _scene = scene;
    _camera = camera;
    _bob = bob;
    _panel = panel;
    _placeBob();

    _ticker = createTicker(_onTick)..start();
    if (mounted) setState(() => _renderer = Renderer.create(device: device));
  }

  void _placeBob() {
    final theta = _pendulum.theta;
    final length = _pendulum.lengthMeters;
    _bob.setPositionFrom(
      Vector3(
        _pivot.x + length * math.sin(theta),
        _pivot.y - length * math.cos(theta),
        _pivot.z,
      ),
    );
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    // The first callback's `elapsed` is already nonzero (a ticker's clock
    // starts when the scheduler binding did, not when this one started), so
    // clamping is what stands in for "skip the first frame" without a bool.
    _pendulum.step(dt.clamp(0.0, 0.05));
    _placeBob();
    unawaited(_panel.tick());
    if (mounted) setState(() {});
  }

  /// The same raycast `flutter3d_template_app`'s own `_tapWidgetSurface`
  /// proved for `tpl-04` — a real tap, through [Raycaster], landing on the
  /// panel exactly the way a player's would in a shipped level.
  bool _tapPanel(Offset local) {
    final size = context.size;
    if (size == null || size.width <= 0.0 || size.height <= 0.0) return false;
    final hit = _raycaster
        .setFromScreen(_camera, local.dx, local.dy, width: size.width, height: size.height)
        .intersectScene(_scene);
    if (hit == null || hit.node != _panel.node) return false;
    final uv = _panel.uvAt(hit.point);
    if (uv == null) return false;

    const pointer = 9001;
    _panel.pipeline.announcePointer(pointer, added: true);
    _panel.pipeline.dispatchAtUv(uv, (local) => PointerDownEvent(pointer: pointer, position: local));
    _panel.pipeline.dispatchAtUv(uv, (local) => PointerUpEvent(pointer: pointer, position: local));
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
    return Scaffold(
      backgroundColor: const Color(0xFF14161A),
      body: Listener(
        onPointerDown: (PointerDownEvent event) => _tapPanel(event.localPosition),
        child: SceneSurface(
          renderer: renderer,
          scene: _scene,
          view: RenderView(camera: _camera),
          settings: () => const RenderSettings(),
          onBeforeFrame: () {},
        ),
      ),
    );
  }
}
