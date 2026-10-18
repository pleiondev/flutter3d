/// The same kind of scene built by hand: nodes added to the engine's scene
/// once the view has opened its device, and turned before every frame.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: SceneWithoutWidgets()));

/// How far the box has turned, in radians.
double turned = 0.0;

/// A view with no 3D widgets in it: a box node added to the engine's scene once
/// the device is open, and turned by [turned] before every frame.
class SceneWithoutWidgets extends StatelessWidget {
  /// Takes nothing: the box is built once the view has opened its device.
  const SceneWithoutWidgets({super.key});

  @override
  Widget build(BuildContext context) => Flutter3dView(
    onCreated: (engine) => engine.scene.add(
      // A shape builds its mesh on the CPU; the device uploads it.
      MeshNode(
        DeviceMesh.upload(engine.device, CuboidShape().build()),
        RenderMaterial(
          baseColor: LinearColor.fromSrgb(0.9, 0.42, 0.28),
          roughness: 0.35,
        ),
        name: 'box',
      ),
    ),
    // After the loop has stepped and before the frame is drawn.
    onFrame: (EngineFrame f) => f.engine.scene.meshes.first
        .setRotationYawPitchRoll(turned += f.seconds, 0.4, 0.0),
  );
}
