/// Decode models off the page in a browser, so the page keeps drawing while
/// a large one is read.
///
///     dart run flutter3d_core:decode_worker web/flutter3d_decode_worker.js
///     flutter run -d chrome -t lib/decode_in_a_worker.dart
///
/// Opt-in: without the script, or where the browser will not start a
/// worker, decoding stays on the page and `WebDecodeWorker.inPlaceReason`
/// says why. Build the script again after upgrading the engine.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() {
  // Natively this does nothing, so the same main runs everywhere.
  WebDecodeWorker.use(Uri.parse('flutter3d_decode_worker.js'));
  runApp(const MaterialApp(home: DecodeInAWorker()));
}

/// The robot on an orbit camera, written exactly as it would be without a
/// worker: whether the decoding happens off the page is decided once, in
/// `main`, and nothing in the scene changes for it.
class DecodeInAWorker extends StatelessWidget {
  /// Takes nothing: the model and the camera are fixed in [build].
  const DecodeInAWorker({super.key});

  @override
  Widget build(BuildContext context) => Scene3D(
    children: <Widget>[
      const OrbitCamera3D(distance: 6.0),
      const Light3D.sun(),
      Model3D(source: 'assets_src/models/RobotExpressive.glb'),
    ],
  );
}
