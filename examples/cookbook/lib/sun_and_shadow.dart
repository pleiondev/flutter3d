/// The sun, a floor and the shadows things cast on it.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: SunAndShadow()));

/// A box and a cylinder on a floor under a sun from the upper left, with no
/// shadow settings at all: a sun casts shadows by default.
class SunAndShadow extends StatelessWidget {
  /// Takes nothing: the sun, the floor and the two shapes are fixed in [build].
  const SunAndShadow({super.key});

  @override
  Widget build(BuildContext context) => Scene3D(
    children: <Widget>[
      Camera3D(position: Vector3(4.0, 4.0, 6.0), target: Vector3.zero()),
      // 15 000 lux from the upper left; a sun casts shadows by default.
      Light3D.sun(direction: Vector3(-0.5, -1.0, -0.4)),
      Material3D(
        baseColor: LinearColor.fromSrgb(0.75, 0.75, 0.7),
        roughness: 0.9,
        children: const <Widget>[
          Mesh3D(shape: PlaneShape(width: 12, depth: 12)),
        ],
      ),
      Material3D(
        baseColor: LinearColor.fromSrgb(0.2, 0.45, 0.85),
        children: <Widget>[
          Mesh3D(shape: CuboidShape(), position: Vector3(-1.0, 0.5, 0.0)),
          Mesh3D(
            shape: const CylinderShape(height: 2.0),
            position: Vector3(1.2, 1.0, -0.5),
          ),
        ],
      ),
    ],
  );
}
