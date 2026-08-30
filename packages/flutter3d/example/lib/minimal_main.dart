/// The smallest flutter3d application: one sphere, one point light.
///
///     flutter run -t lib/minimal_main.dart
///
/// Everything the engine needs is in these seventy lines: open a device, build
/// a scene, render it into a widget. The full demo next door in `main.dart` is
/// the same skeleton grown a model browser; start reading here.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_backend/flutter3d_backend.dart';
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

void main() => runApp(const MinimalApp());

class MinimalApp extends StatelessWidget {
  const MinimalApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(debugShowCheckedModeBanner: false, home: MinimalPage());
}

class MinimalPage extends StatefulWidget {
  const MinimalPage({super.key});

  @override
  State<MinimalPage> createState() => _MinimalPageState();
}

class _MinimalPageState extends State<MinimalPage> {
  // Nullable rather than `late`: the device opens asynchronously, and build
  // runs before it has.
  Renderer? _renderer;
  late final Scene _scene;
  late final RenderView _view;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    // Impeller on desktop and mobile, WebGL2 on the web, and the software
    // rasteriser wherever neither will start — a widget test, a CI runner.
    // This is the one line an application would change to pick by hand.
    final device = await openDevice(width: 1280, height: 720);
    if (!mounted) return device.dispose();

    _scene = Scene(name: 'minimal');

    _scene.add(
      MeshNode(
        DeviceMesh.upload(device, const SphereShape(radius: 1.0).build()),
        Material(
          lighting: LightingModel.pbr,
          baseColor: Vector4(0.9, 0.42, 0.28, 1.0),
          roughness: 0.35,
        ),
        name: 'sphere',
      ),
    );

    // One point light and nothing else, so the falloff is the picture: lit
    // where it faces the light, black where it does not.
    _scene.add(
      LightNode(
        type: LightType.point,
        color: Vector3(0.9, 0.95, 1.0),
        intensity: 16.0,
        range: 20.0,
        name: 'point light',
      )..setPosition(2.0, 2.5, 2.0),
    );

    final camera = _scene.add(CameraNode(name: 'camera'))
      ..setPosition(0.0, 1.2, 3.5)
      ..lookAt(Vector3.zero());
    _view = RenderView(camera: camera);

    setState(() => _renderer = Renderer.create(device: device));
  }

  @override
  void dispose() {
    final renderer = _renderer;
    if (renderer != null) {
      renderer.dispose();
      renderer.device.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
    if (renderer == null) {
      return const ColoredBox(key: Key('opening'), color: Colors.black);
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Physical pixels, or the result is soft on any HiDPI display.
        final frame = renderer.render(
          width: (constraints.maxWidth * dpr).round().clamp(1, 8192),
          height: (constraints.maxHeight * dpr).round().clamp(1, 8192),
          scene: _scene,
          views: <RenderView>[_view],
          settings: const RenderSettings(),
        );
        return renderer.device.present(frame.frame);
      },
    );
  }
}
