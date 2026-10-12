/// The same kind of scene built by hand: nodes added to the engine's scene
/// once the view has opened its device, and turned before every frame.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: SceneWithoutWidgets()));

/// How far the box has turned, in radians.
double turned = 0.0;

class SceneWithoutWidgets extends StatelessWidget {
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
    onFrame: (engine, frame) => engine.scene.meshes.first
        .setRotationYawPitchRoll(turned += frame.seconds, 0.4, 0.0),
  );
}
