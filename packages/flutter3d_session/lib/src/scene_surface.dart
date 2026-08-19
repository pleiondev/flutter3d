import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;

/// The widget that hands a rendered frame to Flutter.
///
/// **The third copy is what made this a package, and the third copy argued
/// against it.** All three applications had these forty lines, and the racing
/// one carried the objection written out:
///
/// > It is not one yet because the three differ in exactly one place, the
/// > shadow settings, and a package whose only parameter is the thing each
/// > caller sets differently is a package that has moved an argument rather
/// > than removed a duplicate.
///
/// That was right about a settings *parameter*, and it is answered by not
/// having one. The three no longer differ in one place either — the crypt turns
/// reflections off, the platformer asks for three cascades at 2048, the circuit
/// sets an exposure and a sky — so a parameter per difference would be four
/// parameters and growing.
///
/// [settings] is a **function called once per frame**, and that is a capability
/// rather than a style: it lets a game derive what a frame is drawn with from
/// where the camera ended up.
///
/// The circuit needs that — its fog colour is the colour of the air *along this
/// view*, so it is only right if it is worked out after the camera has moved.
/// It manages that today by placing its camera in the tick, before `setState`,
/// and computing the colour in the parent's `build`. The crypt cannot: it
/// places its camera in [onBeforeFrame], which runs *after* the parent has
/// built, so anything it derived there would describe the frame before.
///
/// So the two games do the same thing in two different places, and only one of
/// the two places works for both. A function called here is that place.
class SceneSurface extends StatelessWidget {
  const SceneSurface({
    super.key,
    required this.renderer,
    required this.scene,
    required this.view,
    required this.settings,
    required this.onBeforeFrame,
  });

  final Renderer renderer;
  final Scene scene;
  final RenderView view;

  /// What this frame should be drawn with.
  ///
  /// Called after [onBeforeFrame] and immediately before the frame, so anything
  /// derived from where the camera ended up is derived from where it actually
  /// ended up.
  final RenderSettings Function() settings;

  /// The last thing to happen before the frame: place the camera, sync the
  /// visuals, advance whatever is drawn but not simulated.
  final VoidCallback onBeforeFrame;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        onBeforeFrame();
        final frame = renderer.render(
          // Clamped because a zero-sized surface is a real state — a panel
          // being animated open, a window dragged to nothing — and a render
          // target of zero pixels is not.
          width: (constraints.maxWidth * dpr).round().clamp(1, 8192),
          height: (constraints.maxHeight * dpr).round().clamp(1, 8192),
          scene: scene,
          views: <RenderView>[view],
          settings: settings(),
        );
        // From the device rather than painted from an image: a backend whose
        // frame is composited elsewhere has no image to paint, and `present` is
        // the one answer both can give.
        return renderer.device.present(frame.frame);
      },
    );
  }
}
