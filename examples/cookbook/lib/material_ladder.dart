/// One material, five roughnesses and two metals: what the two numbers do.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: MaterialLadder()));

class MaterialLadder extends StatelessWidget {
  const MaterialLadder({super.key});

  @override
  Widget build(BuildContext context) => Scene3D(
    children: <Widget>[
      Camera3D(position: Vector3(0.0, 0.0, 7.0), target: Vector3.zero()),
      const Light3D.sun(),
      for (final metallic in const <double>[0.0, 1.0])
        for (var step = 0; step < 5; step++)
          Material3D(
            // Linear colour: what the shader adds up, not what a picker shows.
            baseColor: LinearColor.fromSrgb(0.8, 0.3, 0.25),
            metallic: metallic,
            roughness: step / 4,
            children: <Widget>[
              Mesh3D(
                shape: const SphereShape(radius: 0.45),
                position: Vector3((step - 2) * 1.1, metallic * 1.2 - 0.6, 0),
              ),
            ],
          ),
    ],
  );
}
