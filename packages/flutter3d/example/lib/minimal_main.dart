/// The smallest flutter3d application: one sphere, one point light.
///
///     flutter run -t lib/minimal_main.dart
///
/// Everything an application needs is one [Flutter3dView]: it opens a device,
/// makes the renderer and the loop, and owns the frame clock, focus, pausing
/// and teardown. What is left here is the scene. The full demo next door in
/// `main.dart` is the engine's own harness, built a layer lower on
/// `SceneSurface`; start reading here.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MinimalApp());

/// The smallest application: [MinimalPage] in a bare [MaterialApp].
class MinimalApp extends StatelessWidget {
  /// The application; it takes nothing.
  const MinimalApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(debugShowCheckedModeBanner: false, home: MinimalPage());
}

/// The one page: a `Flutter3dView` with a sphere lit by one point light.
class MinimalPage extends StatelessWidget {
  /// The page; it takes nothing.
  const MinimalPage({super.key});

  @override
  Widget build(BuildContext context) => Flutter3dView(
    // Impeller on desktop and mobile, WebGL2 on the web, and the software
    // rasteriser wherever neither will start — a widget test, a CI runner.
    // `DeviceSettings(device: …)` is where an application picks by hand.
    view: const ViewSettings(
      placeholder: ColoredBox(key: Key('opening'), color: Colors.black),
    ),
    onCreated: (Flutter3dEngine engine) {
      // The view's own scene comes with a light; this one is lit by its
      // point light alone, so the falloff is the picture: lit where it
      // faces the light, black where it does not.
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
        // The camera moved into the new scene with it.
        ..camera.setPosition(0.0, 1.2, 3.5)
        ..camera.lookAt(Vector3.zero());
    },
  );
}
