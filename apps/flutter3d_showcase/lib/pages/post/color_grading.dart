/// A colour grade: contrast, saturation and warmth for the whole picture, a tint
/// for the shadows and another for the highlights, and the marks a lens leaves.
///
/// Quoted by `color_grading.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ColorGradingDemo extends ShowcaseDemo {
  double contrast = 1.15;
  double saturation = 1.2;
  double temperature = 0.15;
  double coolShadows = 0.03;
  double warmHighlights = 0.15;
  double vignette = 0.45;
  double grain = 0.03;
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
      lift: Vector3(0.0, 0.0, coolShadows),
      gain: Vector3(1.0 + warmHighlights, 1.0 + warmHighlights * 0.4, 1.0),
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
