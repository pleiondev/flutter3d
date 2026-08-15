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
          settings: RenderSettings(
            fog: fog,
            // Three cascades, because this level is a hundred and twenty metres
            // by two hundred and sixty and one map over that is fourteen
            // centimetres of world per texel — which drew the runner's own
            // shadow as a blurred slab beside them, and was reported as the
            // character being drawn twice.
            //
            // A thousand and twenty-four rather than the default two thousand:
            // the atlas is `resolution × cascades` wide, so three cascades at
            // the default would be a six-thousand-pixel HDR texture — a hundred
            // megabytes, on the machine that already had to be taught not to
            // allocate its frame targets late. Three tiles of 1024 cover about
            // forty metres each, which is four centimetres of world per texel
            // against the old fourteen.
            shadows: const ShadowSettings(cascades: 3, resolution: 1024),
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
