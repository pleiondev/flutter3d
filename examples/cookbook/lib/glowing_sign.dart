/// A glowing sign: a surface that emits its own light, in nits, and the
/// bloom that makes it read as bright.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: GlowingSign()));

class GlowingSign extends StatelessWidget {
  const GlowingSign({super.key});

  @override
  Widget build(BuildContext context) => Scene3D(
    clearColor: const LinearColor(0.01, 0.01, 0.02),
    view: const ViewSettings(
      settings: RenderSettings(bloom: BloomSettings(intensity: 0.15)),
    ),
    children: <Widget>[
      Camera3D(position: Vector3(0.0, 0.0, 4.0), target: Vector3.zero()),
      Material3D(
        baseColor: const LinearColor(0.02, 0.02, 0.02),
        emissive: LinearColor.fromSrgb(1.0, 0.2, 0.6),
        // A neon tube is a few thousand candela per square metre.
        emissiveStrength: 3000,
        children: <Widget>[
          Mesh3D(shape: CuboidShape(size: Vector3(2.4, 0.5, 0.1))),
        ],
      ),
    ],
  );
}
