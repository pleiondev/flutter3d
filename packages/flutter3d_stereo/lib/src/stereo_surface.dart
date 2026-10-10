import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart'
    show Flutter3dEngine, Flutter3dView, FrameInfo, ListenerPose;

import 'stereo_rig.dart';
import 'stereo_viewer.dart';

/// The widget that draws a stereo pair and hands it to Flutter: a
/// `Flutter3dView` drawing the [rig]'s two views into one frame.
///
/// The view owns the frame clock, focus, lifecycle and the pause a route
/// change brings; this adds the two things a stereo pair needs on top, and
/// both are the reason it is a widget rather than a parameter:
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
///
/// [renderer] is borrowed, and its device with it: the view leaves both alone
/// when it goes.
class StereoSurface extends StatelessWidget {
  const StereoSurface({
    super.key,
    required this.renderer,
    required this.scene,
    required this.rig,
    required this.settings,
    required this.onBeforeFrame,
    this.fovY = 1.0,
    this.viewer,
    this.screen,
    this.onListenerMoved,
  });

  final Renderer renderer;
  final Scene scene;
  final StereoRig rig;

  /// What the frame should be drawn with, before the stereo rules are applied
  /// to it. Asked whenever the surface is built.
  final RenderSettings Function() settings;

  /// Called every frame before it is drawn: place the rig, advance the
  /// simulation.
  final VoidCallback onBeforeFrame;

  /// What one eye sees vertically, in radians, while no runtime has said
  /// otherwise, and while no [viewer] is given.
  final double fovY;

  /// The holder the phone is in, when it is in one.
  ///
  /// With a holder the frusta come from its lenses: off centre, wider away
  /// from the nose, and taller above the lens axis than below. Without one
  /// they are a centred pair as wide as half the surface, which is right for a
  /// phone held in the hands and wrong the moment there is a lens in front of
  /// it.
  final StereoViewer? viewer;

  /// How big the screen actually is, when a [viewer] is given.
  ///
  /// Left out, it is estimated from the surface's own size at 160 logical
  /// pixels to the inch — see [StereoScreen.fromLogicalPixels] for how much of
  /// an estimate that is. An application that knows the figure should pass it,
  /// because the lens arithmetic is a ratio of two lengths and this is one of
  /// them.
  final StereoScreen? screen;

  /// Told after every frame where the left eye is, which way it faces and
  /// which way is up, as one [ListenerPose]: where the audio listener goes.
  final void Function(ListenerPose ears)? onListenerMoved;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Two, not one: a pair whose target is a single pixel wide has no
        // halves to divide into.
        final width = (constraints.maxWidth * dpr).round().clamp(2, 8192);
        final height = (constraints.maxHeight * dpr).round().clamp(1, 8192);
        if (viewer case final StereoViewer holder?) {
          rig.applyViewer(
            holder,
            screen ??
                StereoScreen.fromLogicalPixels(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                ),
          );
        } else {
          rig.fitToViewport(width: width, height: height, fovY: fovY);
        }
        return Flutter3dView(
          device: renderer.device,
          renderer: renderer,
          scene: scene,
          camera: rig.camera(Eye.left),
          views: rig.views,
          settings: settings().forStereo(),
          onFrame: (Flutter3dEngine engine, FrameInfo frame) => onBeforeFrame(),
          onListenerMoved: onListenerMoved,
        );
      },
    );
  }
}
