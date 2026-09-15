/// The smallest application on the engine: a lit cube you can turn.
///
///     flutter run -d macos
///
/// **Connected to the engine and nothing else.** A device through
/// `openDevice`, a renderer on it, a scene with one mesh and one light, and a
/// camera that orbits when you drag and comes closer when you scroll. No level,
/// no body, no input map, no genre — a project that is a game starts from
/// `packages/flutter3d_game/example` instead, and one that is a viewer, a
/// configurator or a lesson builds what it needs on top of this.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

void main() => runApp(const CubeApp());

class CubeApp extends StatelessWidget {
  const CubeApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'A cube',
    debugShowCheckedModeBanner: false,
    home: CubeScreen(),
  );
}

/// One cube and the light that shows its shape.
///
/// Public and apart from the widget so a test can build it on a device with no
/// window, the same way the application builds it on the one it opened.
Scene buildScene(GraphicsDevice device) => Scene()
  ..add(
    MeshNode(
      DeviceMesh.upload(device, CuboidShape().build()),
      Material(
        name: 'cube',
        lighting: LightingModel.pbr,
        baseColor: Vector4(0.9, 0.42, 0.28, 1.0),
        roughness: 0.4,
      ),
      name: 'cube',
    ),
  )
  ..add(
    LightNode(name: 'sun', intensity: 3.0)
      ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
  );

class CubeScreen extends StatefulWidget {
  const CubeScreen({super.key});

  @override
  State<CubeScreen> createState() => _CubeScreenState();
}

class _CubeScreenState extends State<CubeScreen> {
  final CameraNode _camera = CameraNode(name: 'eye');
  late final RenderView _view = RenderView(
    camera: _camera,
    clearColor: Vector4(0.05, 0.05, 0.07, 1.0),
  );
  late final OrbitController _orbit = OrbitController(
    _camera,
    distance: 3.5,
    yaw: 0.6,
    pitch: 0.45,
  );

  ({Renderer renderer, Scene scene})? _ready;

  /// The device failed to open, or the renderer failed to build on it.
  Object? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      // Through `openDevice` rather than by naming a backend: Impeller or WebGL
      // for the build, and the software rasteriser at run time when flutter_gpu
      // will not start. The size is what that fallback draws at.
      final device = await openDevice(width: 1280, height: 720);
      final scene = buildScene(device)..add(_camera);
      if (!mounted) return;
      setState(
        () =>
            _ready = (renderer: Renderer.create(device: device), scene: scene),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => switch ((_error, _ready)) {
    (final Object error, _) => DidNotStart(
      error,
      background: const Color(0xFF14161A),
      foreground: const Color(0xFFFF8A80),
    ),
    (_, null) => const ColoredBox(
      color: Color(0xFF14161A),
      child: Center(child: CircularProgressIndicator()),
    ),
    (_, (:final renderer, :final scene)?) => Listener(
      onPointerMove: (PointerMoveEvent event) =>
          _orbit.rotate(event.delta.dx, event.delta.dy),
      onPointerSignal: (PointerSignalEvent event) {
        if (event is PointerScrollEvent) {
          _orbit.zoom(event.scrollDelta.dy > 0.0 ? 1.1 : 1.0 / 1.1);
        }
      },
      child: SceneSurface(
        renderer: renderer,
        scene: scene,
        view: _view,
        settings: () => const RenderSettings(),
        onBeforeFrame: () => _orbit.syncProjectionDepth(_camera),
        presentFrame: presentFrame,
      ),
    ),
  };
}
