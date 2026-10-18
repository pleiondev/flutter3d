/// Auto exposure: a meter reads the frame's own brightness and the next
/// frame is exposed by what it found.
///
/// Quoted by `auto_exposure.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

/// The `auto-exposure` page: the post stage exposed by a meter that reads
/// the frame before. Its check is that the luminance pass ran and that the
/// first frame wears the seed exposure.
final class AutoExposureDemo extends ShowcaseDemo {
  /// The grey the meter exposes the frame towards, 0.05 to 0.4.
  double target = 0.18;

  /// How fast the exposure adapts, 0.2 to 6, the same up and down.
  double speed = 1.5;

  /// The exposure the first frame is drawn at, 0.3 to 4, before anything has
  /// been metered.
  double seedExposure = 1.6;

  @override
  void configureView(DemoContext context) => PostStage.frame(context);

  @override
  Scene build(DemoContext context) => PostStage.build(context).scene;

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region seed
    exposure: seedExposure,
    // #endregion seed
    // #region auto
    autoExposure: AutoExposureSettings(
      enabled: true,
      target: target,
      speedUp: speed,
      speedDown: speed,
    ),
    // #endregion auto
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Seed exposure',
      min: 0.3,
      max: 4,
      value: () => seedExposure,
      onChanged: (double v) => seedExposure = v,
    ),
    SliderControl(
      'Target grey',
      min: 0.05,
      max: 0.4,
      value: () => target,
      onChanged: (double v) => target = v,
    ),
    SliderControl(
      'Adaptation speed',
      min: 0.2,
      max: 6,
      value: () => speed,
      onChanged: (double v) => speed = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region reads
    if (!passRan(frame, 'luminance')) {
      throw StateError('the luminance pass did not run: ${frame.skipped}');
    }
    if ((frame.exposure - seedExposure).abs() > 1e-6) {
      throw StateError(
        'the first frame should wear the seed exposure, since nothing has '
        'been metered yet; it reported ${frame.exposure}',
      );
    }
    // #endregion reads
  }
}
