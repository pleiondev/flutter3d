/// Scenes in a scrolling list: each card its own scene, drawn when it is
/// built rather than on every refresh.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: ScenesInAList()));

class ScenesInAList extends StatelessWidget {
  const ScenesInAList({super.key});

  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: 12,
    itemBuilder: (context, i) => Card(
      child: SizedBox(
        height: 160,
        child: Scene3D(
          // Nothing moves, so a frame only when the card is built.
          continuous: false,
          children: <Widget>[
            const Light3D.sun(),
            Material3D(
              baseColor: LinearColor.fromSrgb(i / 12, 0.5, 1 - i / 12),
              roughness: 0.4,
              children: const <Widget>[Mesh3D(shape: SphereShape(radius: 1.2))],
            ),
          ],
        ),
      ),
    ),
  );
}
