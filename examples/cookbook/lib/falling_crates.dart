/// A level with physics: crates that fall onto a floor in the view's step.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show LoopContext, LoopPhase;

void main() => runApp(const MaterialApp(home: FallingCrates()));

class FallingCrates extends StatefulWidget {
  const FallingCrates({super.key});

  @override
  State<FallingCrates> createState() => _FallingCratesState();
}

class _FallingCratesState extends State<FallingCrates> {
  final world = CollisionWorld()..addBox(Vector3.zero(), Vector3(10, 0, 10));
  late final dynamics = Dynamics(world: world);
  final box = CollisionBox(Vector3.all(0.5));
  RigidBody drop(double y) => dynamics.add(
    RigidBody(world: world, shape: box, position: Vector3(y / 5, y, 0)),
  );
  late final crates = [drop(1.0), drop(2.5), drop(4.0)];
  void fall(LoopContext step) => dynamics.step(step.dt);

  @override
  Widget build(BuildContext context) => Scene3D(
    // The bodies move in the loop's fixed step; a frame shows where they are.
    onSceneCreated: (s) =>
        s.engine.loop.addSystem('drop', LoopPhase.physics, fall),
    onFrame: (_) => setState(() {}),
    children: <Widget>[
      Camera3D(position: Vector3(4.0, 3.0, 6.0), target: Vector3(0, 1, 0)),
      const Light3D.sun(),
      Material3D(
        baseColor: LinearColor.fromSrgb(0.7, 0.55, 0.35),
        children: <Widget>[
          const Mesh3D(shape: PlaneShape(width: 10, depth: 10)),
          for (final crate in crates)
            Mesh3D(shape: CuboidShape(), position: crate.position),
        ],
      ),
    ],
  );
}
