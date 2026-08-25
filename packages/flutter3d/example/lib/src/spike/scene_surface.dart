import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';

/// Renders the scene at the widget's physical pixel size and paints the result.
class SceneSurface extends StatelessWidget {
  const SceneSurface({
    super.key,
    required this.renderer,
    required this.scene,
    required this.view,
    required this.settings,
    required this.onFrame,
    this.fixedSize,
  });

  final Renderer renderer;
  final Scene scene;
  final RenderView view;
  final RenderSettings settings;
  final ValueChanged<FrameResult> onFrame;

  /// Renders at this size instead of the widget's, in physical pixels.
  ///
  /// Only the golden path uses it: a reference image recorded on one window and
  /// compared on another would fail for a reason that has nothing to do with
  /// the renderer.
  final Size? fixedSize;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Render at physical resolution: sizing the target in logical pixels
        // would make the result soft on any HiDPI display.
        final width = fixedSize != null
            ? fixedSize!.width.round()
            : (constraints.maxWidth * dpr).round().clamp(1, 8192);
        final height = fixedSize != null
            ? fixedSize!.height.round()
            : (constraints.maxHeight * dpr).round().clamp(1, 8192);

        final frame = renderer.render(
          width: width,
          height: height,
          scene: scene,
          views: <RenderView>[view],
          settings: settings,
        );
        onFrame(frame);

        // From the device, not painted from an image. A backend that composites
        // its frame elsewhere — a browser canvas — has no image to paint, and
        // `present` is the one thing both can answer.
        //
        // `contain` letterboxes rather than stretching, and only the golden
        // path needs it: a golden renders at a size it names, so the frame is
        // 4:3 while the window is not. Stretching one into the other shows a
        // visibly squashed model on screen while the recorded file is perfectly
        // correct, and anybody watching a recording run would reasonably
        // conclude the renderer was broken.
        return renderer.device.present(
          frame.frame,
          fit: fixedSize != null ? BoxFit.contain : BoxFit.fill,
        );
      },
    );
  }
}
