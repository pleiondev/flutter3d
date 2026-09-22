/// Adaptive resolution: `RenderSettings.renderScale` shrinks every target the
/// frame draws into, and `AdaptiveScale` decides the number from how long a
/// frame has been taking.
///
/// Quoted by `adaptive_resolution.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class AdaptiveResolutionDemo extends ShowcaseDemo {
  double simulatedMs = 20.0;
  double scale = 1.0;

  // #region adaptive
  /// A window of one frame, so this page reacts on the very next tick rather
  /// than averaging several — a real game wants a wider window than this.
  final AdaptiveScale _adaptive = AdaptiveScale(
    const AdaptiveScaleSettings(enabled: true, window: 1),
  );
  // #endregion adaptive

  @override
  void configureView(DemoContext context) => PostStage.frame(context);

  @override
  Scene build(DemoContext context) => PostStage.build(context).scene;

  @override
  void update(DemoContext context, double dt) {
    // #region record
    scale = _adaptive.recordFrame((simulatedMs * 1000).round());
    // #endregion record
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region scale
    renderScale: scale,
    // #endregion scale
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Simulated frame cost',
      min: 4,
      max: 40,
      value: () => simulatedMs,
      onChanged: (double v) => simulatedMs = v,
      format: (double v) => '${v.round()} ms',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region size
    final int expectedWidth = (320 * scale).round();
    final int expectedHeight = (180 * scale).round();
    if (frame.frame.width != expectedWidth ||
        frame.frame.height != expectedHeight) {
      throw StateError(
        'asked for a frame scaled to $scale and got '
        '${frame.frame.width}x${frame.frame.height}',
      );
    }
    // #endregion size
  }
}
