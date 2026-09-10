import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;

import 'stereo_rig.dart';

/// The widget that draws a stereo pair and hands it to Flutter.
///
/// `SceneSurface` in `flutter3d_session` with two differences, and both of them
/// are the reason this is not a parameter on that one:
///
/// * it renders a **pair** — two views into one target, left half and right —
///   so the frame it produces is twice as wide as an eye;
/// * it applies [RenderSettings.forStereo] itself rather than trusting the
///   caller to remember. Ambient occlusion and reflections are compiled for the
///   first view and then applied to the whole frame, so on a pair they treat
///   the right eye as if it were the left one. That is a correctness rule about
///   this arrangement, and a rule a caller can forget is a rule that is
///   sometimes broken.
///
/// What it does not do is choose the frusta: [StereoRig.fitToViewport] fills
/// them in from the surface while nothing better is known, and stops the moment
/// a runtime states the real ones.
class StereoSurface extends StatelessWidget {
  const StereoSurface({
    super.key,
    required this.renderer,
    required this.scene,
    required this.rig,
    required this.settings,
    required this.onBeforeFrame,
    this.verticalFieldOfView = 1.0,
  });

  final Renderer renderer;
  final Scene scene;
  final StereoRig rig;

  /// What this frame should be drawn with, before the stereo rules are applied
  /// to it. Called once per frame, after [onBeforeFrame], so anything derived
  /// from where the head ended up is derived from where it actually ended up.
  final RenderSettings Function() settings;

  /// The last thing before the frame: place the rig, advance the simulation.
  final VoidCallback onBeforeFrame;

  /// What one eye sees vertically while no runtime has said otherwise.
  final double verticalFieldOfView;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        onBeforeFrame();
        // Two, not one: a pair whose target is a single pixel wide has no
        // halves to divide into.
        final width = (constraints.maxWidth * dpr).round().clamp(2, 8192);
        final height = (constraints.maxHeight * dpr).round().clamp(1, 8192);
        rig.fitToViewport(
          width: width,
          height: height,
          verticalFieldOfView: verticalFieldOfView,
        );
        final frame = renderer.render(
          width: width,
          height: height,
          scene: scene,
          views: rig.views,
          settings: settings().forStereo(),
        );
        return renderer.device.present(frame.frame);
      },
    );
  }
}
