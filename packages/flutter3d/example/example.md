# One sphere, one point light

The smallest flutter3d application. Open a device, build a scene, render it
into a widget — the whole engine is behind these seventy lines.

Three dependencies, and the second one is the point: `flutter3d` draws and
names no graphics API, so something has to say which backend draws for it.
`flutter3d_backend` is that something — it picks Impeller or WebGL2 by
conditional import and falls back to the software rasteriser at run time, which
is why the code below says `openDevice()` and not `GpuRenderBackend.create()`.

```yaml
dependencies:
  flutter:
    sdk: flutter

  flutter3d: ^0.4.0
  flutter3d_backend: ^0.4.0
  vector_math: ^2.2.0
```

The compiled shader bundle rides inside `flutter3d_impeller`, which
`flutter3d_backend` brings with it, so there is nothing to build and no asset to
declare. On macOS, set `FLTEnableFlutterGPU` and `FLTEnableImpeller` in
`macos/Runner/Info.plist`, or the app draws through the software fallback and
says so on the console.

```dart
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
    // rasteriser wherever neither will start.
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
```

Runnable as `example/lib/minimal_main.dart`:

```sh
flutter run -t lib/minimal_main.dart
```

The full model browser — every lighting model, shadows, bloom, skinning and
the debug overlay — is `example/lib/main.dart` in the same directory.
