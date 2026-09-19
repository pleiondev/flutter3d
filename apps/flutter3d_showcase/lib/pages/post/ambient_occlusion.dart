/// Ambient occlusion: the ambient term darkened wherever a surface cannot see
/// much of the sky.
///
/// Quoted by `ambient_occlusion.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class AmbientOcclusionDemo extends ShowcaseDemo {
  double strength = 0.9;
  int blurTaps = 0;

  @override
  void configureView(DemoContext context) =>
      PostStage.frame(context, distance: 6.0);

  @override
  Scene build(DemoContext context) {
    // #region ambient
    final Scene scene = PostStage.build(context).scene;
    scene.ambientIntensity = 0.6;
    // #endregion ambient
    return scene;
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    ambientOcclusion: AmbientOcclusionSettings(
      enabled: true,
      strength: strength,
      blurTaps: blurTaps,
    ),
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Strength',
      min: 0,
      max: 1,
      value: () => strength,
      onChanged: (double v) => strength = v,
    ),
    SliderControl(
      'Blur taps',
      min: 0,
      max: 8,
      divisions: 8,
      value: () => blurTaps.toDouble(),
      onChanged: (double v) => blurTaps = v.round(),
      format: (double v) => '${v.round()}',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region ran
    if (!passRan(frame, 'ssao')) {
      throw StateError('the ssao pass did not run: ${frame.skipped}');
    }
    if (blurTaps > 0 && !passRan(frame, 'ssao blur')) {
      throw StateError(
        'blur taps were asked for and the blur pass did not run',
      );
    }
    // #endregion ran
  }
}
