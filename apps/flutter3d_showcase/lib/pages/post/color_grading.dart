/// A colour grade: contrast, saturation and warmth for the whole picture, a tint
/// for the shadows and another for the highlights, and the marks a lens leaves.
///
/// Quoted by `color_grading.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

/// The `color-grading` page: the post stage through a grade and the marks of
/// a lens. Its check is that the composite pass, which grades, ran.
final class ColorGradingDemo extends ShowcaseDemo {
  /// The grade's contrast, 0.5 to 1.8; 1 leaves it as drawn.
  double contrast = 1.15;

  /// The grade's saturation, 0 to 2; 0 is grey and 1 leaves it as drawn.
  double saturation = 1.2;

  /// The grade's warmth, -1 (cooler) to 1 (warmer).
  double temperature = 0.15;

  /// How much blue is lifted into the shadows, 0 to 0.15.
  double coolShadows = 0.03;

  /// How much the highlights' gain is pushed to red, and less to green, 0 to
  /// 0.5.
  double warmHighlights = 0.15;

  /// How dark the corners go, 0 to 1.
  double vignette = 0.45;

  /// How strong the film grain is, 0 to 0.1.
  double grain = 0.03;

  /// How far the colours fringe apart towards the edges, 0 to 0.015; the
  /// grade's `chromaticAberration`.
  double aberration = 0.004;

  @override
  void configureView(DemoContext context) => PostStage.frame(context);

  @override
  Scene build(DemoContext context) => PostStage.build(context).scene;

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    look: LookSettings(
      // #region whole
      contrast: contrast,
      saturation: saturation,
      temperature: temperature,
      // #endregion whole
      // #region ranges
      lift: LinearColor(0.0, 0.0, coolShadows),
      gain: LinearColor(1.0 + warmHighlights, 1.0 + warmHighlights * 0.4, 1.0),
      // #endregion ranges
      // #region lens
      vignette: vignette,
      grain: grain,
      chromaticAberration: aberration,
      // #endregion lens
    ),
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Contrast',
      min: 0.5,
      max: 1.8,
      value: () => contrast,
      onChanged: (double v) => contrast = v,
    ),
    SliderControl(
      'Saturation',
      min: 0,
      max: 2,
      value: () => saturation,
      onChanged: (double v) => saturation = v,
    ),
    SliderControl(
      'Temperature',
      min: -1,
      max: 1,
      value: () => temperature,
      onChanged: (double v) => temperature = v,
    ),
    SliderControl(
      'Cool shadows',
      min: 0,
      max: 0.15,
      value: () => coolShadows,
      onChanged: (double v) => coolShadows = v,
    ),
    SliderControl(
      'Warm highlights',
      min: 0,
      max: 0.5,
      value: () => warmHighlights,
      onChanged: (double v) => warmHighlights = v,
    ),
    SliderControl(
      'Vignette',
      min: 0,
      max: 1,
      value: () => vignette,
      onChanged: (double v) => vignette = v,
    ),
    SliderControl(
      'Grain',
      min: 0,
      max: 0.1,
      value: () => grain,
      onChanged: (double v) => grain = v,
    ),
    SliderControl(
      'Colour fringe',
      min: 0,
      max: 0.015,
      value: () => aberration,
      onChanged: (double v) => aberration = v,
      format: (double v) => v.toStringAsFixed(3),
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (!passRan(frame, 'composite')) {
      throw StateError('the composite pass, which grades the frame, is absent');
    }
  }
}
