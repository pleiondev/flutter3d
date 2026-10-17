/// The smallest application on the engine: a lit cube you can turn.
///
///     flutter run -d macos
///
/// **One [Flutter3dView] and nothing else.** The view opens the device (the
/// GPU where it starts, the software rasteriser where it does not), makes
/// the renderer and the loop, and owns the frame clock, focus, pausing and
/// teardown; this file hands it a scene with one mesh and one light and a
/// camera that orbits when you drag and comes closer when you scroll. No
/// level, no body, no input map, no genre.
///
/// The other starting points sit beside it: a digital twin fed by a real
/// source in `lib/twin_main.dart`, a laboratory on the accurate profile in
/// `packages/flutter3d_education/example/lib/pendulum_main.dart`, and a
/// game in `packages/flutter3d_game/example`.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

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
/// window, the same way the application builds it on the one the view opened.
Scene buildScene(GraphicsDevice device) => Scene()
  ..add(
    MeshNode(
      DeviceMesh.upload(device, CuboidShape().build()),
      RenderMaterial(
        name: 'cube',
        lighting: LightingModel.pbr,
        baseColor: LinearColor.fromSrgb(0.9, 0.42, 0.28, 1.0),
        roughness: 0.4,
      ),
      name: 'cube',
    ),
  )
  ..add(
    LightNode(name: 'sun', intensity: 3.0 * LightNode.defaultIntensity)
      ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
  );

class CubeScreen extends StatefulWidget {
  const CubeScreen({super.key});

  @override
  State<CubeScreen> createState() => _CubeScreenState();
}

class _CubeScreenState extends State<CubeScreen> {
  final CameraNode _camera = CameraNode(name: 'eye');
  late final OrbitController _orbit = OrbitController(
    _camera,
    distance: 3.5,
    yaw: 0.6,
    pitch: 0.45,
  );

  @override
  Widget build(BuildContext context) => Listener(
    onPointerMove: (PointerMoveEvent event) =>
        _orbit.rotate(event.delta.dx, event.delta.dy),
    onPointerSignal: (PointerSignalEvent event) {
      if (event is PointerScrollEvent) {
        _orbit.zoom(event.scrollDelta.dy > 0.0 ? 1.1 : 1.0 / 1.1);
      }
    },
    child: Flutter3dView(
      camera: _camera,
      // The scene needs the device to upload its mesh to, so it is made once
      // the view has opened one; the camera moves into it with the swap.
      onCreated: (Flutter3dEngine engine) {
        engine.scene = buildScene(engine.device);
        engine.view.clearColor = LinearColor.fromSrgb(0.05, 0.05, 0.07, 1.0);
      },
      onBeforeFrame: (_) => _orbit.syncProjectionDepth(_camera),
      view: ViewSettings(
        placeholder: const ColoredBox(
          color: Color(0xFF14161A),
          child: Center(child: CircularProgressIndicator()),
        ),
        failure: (Object error) => DidNotStart(
          error,
          background: const Color(0xFF14161A),
          foreground: const Color(0xFFFF8A80),
        ),
      ),
    ),
  );
}
