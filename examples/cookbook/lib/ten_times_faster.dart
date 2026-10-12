/// Ten times faster: one clock for the whole scene, so the clips, the
/// particles, the loop and `onFrame` all run at ten seconds a second.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show TimeSource;

void main() => runApp(MaterialApp(home: TenTimesFaster()));

class TenTimesFaster extends StatelessWidget {
  TenTimesFaster({super.key});

  /// Made once: a time source carries on from where it was.
  final TimeSource tenfold = TimeSource.scaled(10);

  @override
  Widget build(BuildContext context) => Scene3D(
    time: tenfold,
    children: <Widget>[
      const OrbitCamera3D(distance: 6.0),
      const Light3D.sun(),
      Model3D(
        source: 'assets_src/models/RobotExpressive.glb',
        animation: 'Walking',
      ),
    ],
  );
}
