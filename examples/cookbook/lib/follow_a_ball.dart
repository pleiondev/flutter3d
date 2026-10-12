/// An orbit camera that follows a bouncing ball, and stays where the person
/// turned it.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: FollowABall()));

class FollowABall extends StatefulWidget {
  const FollowABall({super.key});

  @override
  State<FollowABall> createState() => _FollowABallState();
}

class _FollowABallState extends State<FollowABall> {
  final ball = Vector3(0.0, 3.0, 0.0), speed = Vector3(1.5, 0.0, 0.0);

  void bounce(double dt) => setState(() {
    speed.y -= 9.81 * dt;
    ball.addScaled(speed, dt);
    if (ball.y < 0.3) speed.y = speed.y.abs() * 0.9;
  });

  @override
  Widget build(BuildContext context) => Scene3D(
    onFrame: (_, frame) => bounce(frame.seconds),
    children: <Widget>[
      // The target follows on every build; distance and angle are the person's.
      OrbitCamera3D(target: ball.clone(), distance: 8.0),
      const Light3D.sun(),
      Material3D(
        baseColor: LinearColor.fromSrgb(0.3, 0.6, 0.35),
        children: <Widget>[
          Mesh3D(shape: const SphereShape(radius: 0.3), position: ball.clone()),
          const Mesh3D(shape: PlaneShape(width: 200, depth: 200)),
        ],
      ),
    ],
  );
}
