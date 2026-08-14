/// The widget that hands a rendered frame to Flutter.
///
/// Extracted from `main.dart` because it is the seam between the renderer and
/// the widget tree, and nothing about it is this game's: the same forty lines
/// belong to every application that draws a `Scene`.
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
          settings: RenderSettings(
            // Off until the surface buffer carries roughness. Without it the
            // shader reflects off rough stone as readily as off a wet floor,
            // and the walls light up instead of the floor.
            // Off. The march tests only the front-most depth, so a ray that
            // passes behind a wall counts as hitting it and picks up whatever
            // is drawn at that pixel — a highlight straight through solid
            // stone. The thickness bound was meant to stop that, but depth is
            // compressed at distance and 0.006 spans metres of world out
            // there. It needs a view-space test, not a depth-space one.
            reflections: const ReflectionSettings(),
            // Straight from the document. A crypt without fog is a crypt with
            // a visible far wall, and the far wall is the thing an author
            // least wants seen.
            fog: fog,
          ),
        );
        // From the device rather than painted from an image: a backend whose
        // frame is composited elsewhere has no image to paint, and `present` is
        // the one answer both can give.
        return renderer.device.present(frame.frame);
      },
    );
  }
}
