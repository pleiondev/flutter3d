import 'package:vector_math/vector_math.dart';

import '../scene/camera_node.dart';

/// How a sub-list of draws is ordered.
///
/// Modes rather than one hardcoded policy, following PlayCanvas: the right order
/// depends on what is being drawn, and the caller knows that better than the
/// renderer does.
enum SortMode {
  /// Group by pipeline, then material, then near-to-far. The default for opaque
  /// geometry: it minimises pipeline changes, which here are the most
  /// expensive state change there is.
  stateThenDepth,

  /// Far-to-near. Required for correct alpha blending.
  backToFront,

  /// Near-to-far, to let early-z reject more fragments.
  frontToBack,

  /// Respect only `Material.drawBucket`, leaving the rest in submission order.
  manual,

  /// Submission order.
  none,
}

/// One camera rendering one target.
///
/// Splitting this out from the renderer is what makes multiple viewports,
/// off-screen passes and eventually shadow maps ordinary rather than special:
/// a shadow pass is a render view whose camera happens to be a light.
final class RenderView {
  RenderView({
    required this.camera,
    this.viewportFraction = const ViewportRect(0.0, 0.0, 1.0, 1.0),
    this.layerMask = ~0,
    this.priority = 0,
    Vector4? clearColor,
    this.opaqueSort = SortMode.stateThenDepth,
    this.transparentSort = SortMode.backToFront,
  }) : clearColor = clearColor ?? Vector4(0.055, 0.062, 0.078, 1.0);

  CameraNode camera;

  /// Normalized rectangle within the target, as in Babylon. Fractions rather
  /// than pixels so a view survives a resize unchanged.
  ViewportRect viewportFraction;

  /// Nodes are drawn only where `node.layerMask & view.layerMask != 0`.
  int layerMask;

  /// Views are rendered in ascending priority, like PlayCanvas camera priority.
  int priority;

  Vector4 clearColor;

  SortMode opaqueSort;
  SortMode transparentSort;
}

/// Normalized viewport rectangle.
///
/// A local type rather than `dart:ui`'s `Rect`, so the render layer stays free of
/// Flutter's UI library and remains usable from a plain Dart test. Named
/// distinctly on purpose: `Rect` would collide with Flutter's in every file that
/// imports both.
final class ViewportRect {
  /// Fractions of the target, so every one of these belongs in `[0, 1]` and
  /// the rectangle has to stay inside it.
  ///
  /// Asserted rather than clamped, and rather than nothing — which is what it
  /// was. A rectangle running off the attachment is clipped by the driver, so
  /// it produces a picture rather than an error, and a different picture on
  /// each backend: the split-screen that is half off the bottom looks like a
  /// layout bug in the application and is a value nobody checked.
  const ViewportRect(this.x, this.y, this.width, this.height)
    : assert(x >= 0.0 && x <= 1.0, 'x is a fraction of the target'),
      assert(y >= 0.0 && y <= 1.0, 'y is a fraction of the target'),
      assert(width > 0.0 && width <= 1.0, 'width is a fraction, and not zero'),
      assert(
        height > 0.0 && height <= 1.0,
        'height is a fraction, and not zero',
      ),
      assert(x + width <= 1.0, 'the viewport runs off the right of the target'),
      assert(
        y + height <= 1.0,
        'the viewport runs off the bottom of the target',
      );

  final double x;
  final double y;
  final double width;
  final double height;

  /// Whether this viewport is the whole target.
  ///
  /// Nothing here asks: the engine sets the viewport either way and lets the
  /// hardware clip. It is for a caller writing a pass of its own that has a
  /// faster path when it owns the whole target — a full-target clear, or a blit
  /// that can skip the scissor — and needs to know which case it is in.
  bool get isFullTarget =>
      x == 0.0 && y == 0.0 && width == 1.0 && height == 1.0;

  @override
  String toString() => 'ViewportRect($x, $y, $width, $height)';
}
