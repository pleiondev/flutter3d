/// The widget that hands a rendered frame to Flutter.
///
/// The same forty lines as the dungeon's and the platformer's, and this is the
/// third copy — which by the rule this repository keeps about coincidences is
/// the one that says it should be a package. It is not one yet because the
/// three differ in exactly one place, the shadow settings, and a package whose
/// only parameter is the thing each caller sets differently is a package that
/// has moved an argument rather than removed a duplicate.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;

import 'backend.dart';

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
            fog: fog,
            // Three cascades over a circuit a kilometre round. One map over
            // that is metres of world per texel, which draws a car's own shadow
            // as a slab beside it; three tiles put the near one over the part
            // of the track anybody is looking at.
            shadows: const ShadowSettings(
              cascades: kShadowCascades,
              resolution: kShadowResolution,
            ),
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
