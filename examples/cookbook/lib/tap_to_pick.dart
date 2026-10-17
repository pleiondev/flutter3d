/// Tap a shape to pick it: the nearest surface under the finger answers.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: TapToPick()));

class TapToPick extends StatefulWidget {
  const TapToPick({super.key});

  @override
  State<TapToPick> createState() => _TapToPickState();
}

class _TapToPickState extends State<TapToPick> {
  int? picked;

  @override
  Widget build(BuildContext context) => Scene3D(
    children: <Widget>[
      Camera3D(position: Vector3(0.0, 2.0, 6.0), target: Vector3.zero()),
      const Light3D.sun(),
      for (var i = 0; i < 3; i++)
        Material3D(
          key: ValueKey<int>(i),
          baseColor: picked == i
              ? LinearColor.fromSrgb(0.95, 0.55, 0.1)
              : LinearColor.fromSrgb(0.5, 0.55, 0.6),
          children: <Widget>[
            Mesh3D(
              shape: CuboidShape(),
              position: Vector3((i - 1) * 1.6, 0.0, 0.0),
              onTap: (tap) => setState(() => picked = i),
            ),
          ],
        ),
    ],
  );
}
