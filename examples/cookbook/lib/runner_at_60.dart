/// A runner at 60 fps on a phone: a frame rate cap that lands on whole
/// refreshes, a lower render scale, and the camera following the runner.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: RunnerAt60()));

/// A capsule running down an endless track with the camera behind it, under a
/// frame rate cap of 60 and three quarters of the pixels: the settings a phone
/// game starts from.
class RunnerAt60 extends StatefulWidget {
  /// Takes nothing: the runner moves at six metres a second.
  const RunnerAt60({super.key});

  @override
  State<RunnerAt60> createState() => _RunnerAt60State();
}

class _RunnerAt60State extends State<RunnerAt60> {
  double run = 0.0;

  @override
  Widget build(BuildContext context) => Scene3D(
    view: const ViewSettings(
      // Every other refresh on a 120 Hz screen, every one on 60 Hz.
      frameRateCap: 60,
      // Three quarters of the pixels, and the bloom a phone can skip.
      settings: RenderSettings(
        renderScale: 0.75,
        bloom: BloomSettings(enabled: false),
      ),
    ),
    onFrame: (EngineFrame frame) => setState(() => run += 6.0 * frame.seconds),
    children: <Widget>[
      Camera3D(position: Vector3(0, 2.5, 5 - run), target: Vector3(0, 1, -run)),
      const Light3D.sun(),
      Material3D(
        baseColor: LinearColor.fromSrgb(0.85, 0.4, 0.2),
        children: <Widget>[
          Mesh3D(shape: const CapsuleShape(), position: Vector3(0, 0.6, -run)),
          // The track is laid a tile ahead of the runner and taken up behind.
          for (var tile = run ~/ 4; tile < run ~/ 4 + 12; tile++)
            Mesh3D(
              key: ValueKey<int>(tile),
              shape: const PlaneShape(width: 3, depth: 3.8),
              position: Vector3(0, 0, -4.0 * tile),
            ),
        ],
      ),
    ],
  );
}
