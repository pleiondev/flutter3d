# One sphere, one point light

The smallest flutter3d application. One `Flutter3dView` opens the device,
makes the renderer and the loop, and owns the frame clock, focus, pausing and
teardown; what is left to write is the scene.

Two dependencies besides Flutter, and the second one is the point: `flutter3d`
draws and names no graphics API, so something has to say which backend draws
for it. `flutter3d_app` is that something: it picks Impeller or WebGL2 by
conditional import and falls back to the software rasteriser at run time, and
`Flutter3dView` is its widget.

```yaml
dependencies:
  flutter:
    sdk: flutter

  flutter3d: ^1.0.0-rc.1
  flutter3d_app: ^1.0.0-rc.1
```

The compiled shader bundle rides inside `flutter3d_impeller`, which
`flutter3d_app` brings with it, so there is nothing to build and no asset to
declare. On macOS, set `FLTEnableFlutterGPU` and `FLTEnableImpeller` in
`macos/Runner/Info.plist`, or the app draws through the software fallback and
says so in a banner over the picture.

```dart
import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MinimalApp());

class MinimalApp extends StatelessWidget {
  const MinimalApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(debugShowCheckedModeBanner: false, home: MinimalPage());
}

class MinimalPage extends StatelessWidget {
  const MinimalPage({super.key});

  @override
  Widget build(BuildContext context) => Flutter3dView(
    view: const ViewSettings(
      placeholder: ColoredBox(key: Key('opening'), color: Colors.black),
    ),
    onCreated: (Flutter3dEngine engine) {
      engine
        ..scene = (Scene(name: 'minimal')
          ..add(
            MeshNode(
              DeviceMesh.upload(
                engine.device,
                const SphereShape(radius: 1.0).build(),
              ),
              RenderMaterial(
                lighting: LightingModel.pbr,
                baseColor: LinearColor.fromSrgb(0.9, 0.42, 0.28, 1.0),
                roughness: 0.35,
              ),
              name: 'sphere',
            ),
          )
          ..add(
            LightNode(
              type: LightType.point,
              color: LinearColor(0.9, 0.95, 1.0),
              intensity: 16.0 * LightNode.defaultIntensity,
              range: 20.0,
              name: 'point light',
            )..setPosition(2.0, 2.5, 2.0),
          ))
        ..camera.setPosition(0.0, 1.2, 3.5)
        ..camera.lookAt(Vector3.zero());
    },
  );
}
```

Runnable as `example/lib/minimal_main.dart`:

```sh
flutter run -t lib/minimal_main.dart
```

Three more starting points sit in the other packages' examples: a digital
twin fed by a real REST source, with its history on a tape and a timeline to
scrub it (`flutter3d_app/example/lib/twin_main.dart`); a pendulum laboratory
on the accurate profile with a clock moved by hand
(`flutter3d_education/example/lib/pendulum_main.dart`); and a level to walk
through, the seed of a game (`flutter3d_game/example`).

The full model browser in the same directory, `example/lib/main.dart`, is the
engine's own harness: every lighting model, shadows, bloom, skinning and the
debug overlay, built a layer lower on `SceneSurface` because it drives the
golden runs.
