/// The widget that hands a rendered frame to Flutter.
///
/// The same forty lines as the dungeon's, and that is the argument for both of
/// them: nothing in here is either game's, and a third application would copy
/// it a third time before it was worth a package.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;

class SceneSurface extends StatelessWidget {
  const SceneSurface({
    super.key,
    required this.renderer,
    required this.scene,
    required this.view,
    required this.fog,
    required this.onBeforeFrame,
  });

  final Renderer renderer;
  final Scene scene;
  final RenderView view;
  final FogSettings fog;
  final VoidCallback onBeforeFrame;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        onBeforeFrame();
        final frame = renderer.render(
          width: (constraints.maxWidth * dpr).round().clamp(1, 8192),
          height: (constraints.maxHeight * dpr).round().clamp(1, 8192),
          scene: scene,
          views: <RenderView>[view],
          settings: RenderSettings(fog: fog),
        );
        // From the device rather than painted from an image: a backend whose
        // frame is composited elsewhere has no image to paint, and `present` is
        // the one answer both can give.
        return renderer.device.present(frame.frame);
      },
    );
  }
}
