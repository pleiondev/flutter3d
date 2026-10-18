/// Turn a shape a little every frame, by the seconds the frame says passed.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: SpinAShape()));

/// A gold torus turned a little before every frame, by the seconds the frame
/// says have passed, so it turns at the same speed whatever the refresh rate.
class SpinAShape extends StatefulWidget {
  /// Takes nothing: the torus turns at 0.8 radians a second.
  const SpinAShape({super.key});

  @override
  State<SpinAShape> createState() => _SpinAShapeState();
}

class _SpinAShapeState extends State<SpinAShape> {
  double angle = 0.0; // Radians turned so far.

  @override
  Widget build(BuildContext context) => Scene3D(
    // Before every frame, with the seconds since the last one.
    onFrame: (EngineFrame frame) =>
        setState(() => angle += frame.seconds * 0.8),
    children: <Widget>[
      Camera3D(position: Vector3(0.0, 1.5, 4.0), target: Vector3.zero()),
      const Light3D.sun(),
      Material3D(
        baseColor: LinearColor.fromSrgb(0.95, 0.75, 0.2),
        metallic: 1.0,
        children: <Widget>[
          Mesh3D(
            shape: const TorusShape(radius: 0.8, tubeRadius: 0.3),
            rotation: Quaternion.euler(angle, 0.4, 0.0),
          ),
        ],
      ),
    ],
  );
}
