/// Load a glTF and orbit it: drag to turn, pinch or scroll to come closer.
///
///     flutter run -d macos -t lib/load_and_orbit.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: LoadAndOrbit()));

/// The robot from `assets_src/` under the sun, on an orbit camera the person
/// turns with a drag and moves in and out with a pinch or the wheel.
class LoadAndOrbit extends StatelessWidget {
  /// Takes nothing: the model path and the camera are fixed in [build].
  const LoadAndOrbit({super.key});

  @override
  Widget build(BuildContext context) => Scene3D(
    children: <Widget>[
      // Turned by a drag, moved in and out by a pinch or the wheel.
      const OrbitCamera3D(distance: 6.0),
      const Light3D.sun(),
      // A path under assets_src/: the build hook converts it, and a debug
      // build that has not run the hook yet decodes the source itself.
      Model3D(source: 'assets_src/models/RobotExpressive.glb'),
    ],
  );
}
