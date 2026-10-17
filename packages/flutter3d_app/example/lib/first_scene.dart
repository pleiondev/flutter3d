/// A first scene in about ten lines: `Flutter3dView` opens the device, owns
/// the loop, the focus and the teardown, and hands back the engine to fill.
///
///     flutter run -d macos -t lib/first_scene.dart
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(
  Flutter3dView(
    onCreated: (engine) => engine.scene.add(
      MeshNode(
        DeviceMesh.upload(engine.device, CuboidShape().build()),
        RenderMaterial(baseColor: LinearColor.fromSrgb(0.9, 0.5, 0.2, 1.0)),
      ),
    ),
  ),
);
