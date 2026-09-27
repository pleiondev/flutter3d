/// Spatial upscaling: a frame drawn below full size brought up to it by an
/// edge-directed filter instead of a plain stretch.
///
/// Quoted by `spatial_upscale.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class SpatialUpscaleDemo extends ShowcaseDemo {
  bool upscale = true;
  double renderScale = 0.5;
  double sharpen = 0.2;

  @override
  void configureView(DemoContext context) =>
      PostStage.frame(context, distance: 6.0);

  @override
  Scene build(DemoContext context) {
    // #region stage
    final Scene scene = PostStage.build(context, shadows: true).scene;
    // #endregion stage
    return scene;
  }

  // #region settings
  RenderSettings _settings() => RenderSettings(
    renderScale: renderScale,
    spatialUpscale: SpatialUpscaleSettings(enabled: upscale, sharpen: sharpen),
  );
  // #endregion settings

  @override
  RenderSettings settings(DemoContext context) => _settings();

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Upscale',
      value: () => upscale,
      onChanged: (bool v) => upscale = v,
    ),
    SliderControl(
      'Render scale',
      min: 0.25,
      max: 1,
      value: () => renderScale,
      onChanged: (double v) => renderScale = v,
      format: (double v) => '${(v * 100).round()}%',
    ),
    SliderControl(
      'Sharpen',
      min: 0,
      max: 1,
      value: () => sharpen,
      onChanged: (double v) => sharpen = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region runs
    if (SpatialUpscaleSettings.runsFor(_settings())) {
      expectPassOrDecline(frame, 'spatial upscale');
    } else if (passRan(frame, 'spatial upscale')) {
      throw StateError('the upscale ran on a frame that does not need it');
    }
    // #endregion runs
  }
}
