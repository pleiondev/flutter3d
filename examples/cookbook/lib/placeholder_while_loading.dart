/// Something in its place while a model loads, and a word when it has.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: PlaceholderWhileLoading()));

/// The robot, with a grey capsule standing where it will be until it has
/// loaded, and a debug line counting its meshes once it has.
class PlaceholderWhileLoading extends StatelessWidget {
  /// Takes nothing: the model, the placeholder and the callback are fixed in
  /// [build].
  const PlaceholderWhileLoading({super.key});

  @override
  Widget build(BuildContext context) => Scene3D(
    children: <Widget>[
      const OrbitCamera3D(distance: 6.0),
      const Light3D.sun(),
      Model3D(
        source: 'assets_src/models/RobotExpressive.glb',
        // A 3D widget, taken out when the model is in the scene.
        placeholder: Material3D(
          baseColor: LinearColor.fromSrgb(0.6, 0.6, 0.6),
          children: <Widget>[
            Mesh3D(
              shape: const CapsuleShape(height: 2.0),
              position: Vector3(0, 1.5, 0),
            ),
          ],
        ),
        onLoaded: (instance) =>
            debugPrint('${instance.meshes.length} meshes in'),
      ),
    ],
  );
}
