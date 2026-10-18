/// A pendulum with a length slider: the period follows the square root of
/// the length, and you can watch it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: PendulumSlider()));

/// A pendulum bob swung by its own integration every frame, with a slider that
/// changes its length while it swings. A longer pendulum swings slower, by the
/// square root of its length.
class PendulumSlider extends StatefulWidget {
  /// Takes nothing: the pendulum starts a metre and a half long, half a radian
  /// out.
  const PendulumSlider({super.key});

  @override
  State<PendulumSlider> createState() => _PendulumSliderState();
}

class _PendulumSliderState extends State<PendulumSlider> {
  double length = 1.5, angle = 0.5, speed = 0.0;

  // Semi-implicit Euler at the frame's seconds, which keeps the energy.
  void swing(double dt) => setState(() {
    speed -= 9.81 / length * math.sin(angle) * dt;
    angle += speed * dt;
  });

  void resize(double to) => setState(() => length = math.max(to, 0.3));

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Scene3D(
      onFrame: (EngineFrame frame) => swing(frame.seconds),
      children: <Widget>[
        Camera3D(position: Vector3(0, -1, 6), target: Vector3(0, -1, 0)),
        const Light3D.sun(),
        Material3D(
          baseColor: LinearColor.fromSrgb(0.8, 0.6, 0.3),
          metallic: 1.0,
          children: <Widget>[
            Mesh3D(
              shape: const SphereShape(radius: 0.2),
              position: Vector3(math.sin(angle), -math.cos(angle), 0) * length,
            ),
          ],
        ),
      ],
    ),
    bottomNavigationBar: Slider(value: length, max: 3, onChanged: resize),
  );
}
