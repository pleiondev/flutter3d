/// `minimal_main.dart`'s scene written as widgets — `P10`.
///
///     flutter run -t lib/widgets_main.dart
///
/// The same sphere and point light, without opening a device, keeping a
/// renderer or building the graph by hand: `Scene3D` does those, and the
/// scene is the widgets below it. Tap to turn the sphere from rough copper to
/// polished blue and back. The rebuild keeps the sphere's node and its
/// material object — `Material3D` writes the new values into the one it made
/// — which is what a game relying on either across a rebuild needs.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

void main() => runApp(const WidgetsApp3D());

class WidgetsApp3D extends StatelessWidget {
  const WidgetsApp3D({super.key, this.onCreated});

  /// Handed the scene once it exists; the smoke test reads the graph here.
  final void Function(Scene3DController controller)? onCreated;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: WidgetsPage(onCreated: onCreated),
  );
}

class WidgetsPage extends StatefulWidget {
  const WidgetsPage({super.key, this.onCreated});

  final void Function(Scene3DController controller)? onCreated;

  @override
  State<WidgetsPage> createState() => _WidgetsPageState();
}

class _WidgetsPageState extends State<WidgetsPage> {
  bool _polished = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    // Opaque: the surface the frame is shown on takes no hits of its own.
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _polished = !_polished),
    child: Scene3D(
      // Drawn when this page rebuilds; nothing here moves on its own.
      continuous: false,
      onCreated: widget.onCreated,
      placeholder: const ColoredBox(key: Key('opening'), color: Colors.black),
      children: <Widget>[
        Camera3D(position: Vector3(0.0, 1.2, 3.5), target: Vector3.zero()),
        // One point light and nothing else, so the falloff is the picture.
        Light3D.point(
          position: Vector3(2.0, 2.5, 2.0),
          color: Vector3(0.9, 0.95, 1.0),
          intensity: 16.0,
          range: 20.0,
        ),
        Material3D(
          key: const ValueKey<String>('sphere material'),
          baseColor: _polished
              ? Vector4(0.25, 0.45, 0.9, 1.0)
              : Vector4(0.9, 0.42, 0.28, 1.0),
          roughness: _polished ? 0.1 : 0.35,
          metallic: _polished ? 1.0 : 0.0,
          children: const <Widget>[
            Mesh3D(
              key: ValueKey<String>('sphere'),
              shape: SphereShape(radius: 1.0),
              name: 'sphere',
            ),
          ],
        ),
      ],
    ),
  );
}
