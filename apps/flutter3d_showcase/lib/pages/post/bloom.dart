/// Bloom: the light that is brighter than the display spills over its edge.
///
/// Quoted by `bloom.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

/// The `bloom` page: the post stage and a lamp brighter than the display.
/// Its check is that the bloom pass ran.
final class BloomDemo extends ShowcaseDemo {
  /// The brightness above which light blooms, 0 to 4.
  double threshold = 1.0;

  /// How much of the bloom is added back to the frame, 0 to 1.5.
  double intensity = 0.35;

  /// How warm the wide part of the bloom is made, as film's halation makes it,
  /// 0 to 1; the core around a highlight keeps its colour.
  double halation = 0.0;

  /// How many halving levels the bloom spreads over, 1 to 7: more levels
  /// reach further.
  int levels = 5;

  @override
  void configureView(DemoContext context) => PostStage.frame(context);

  @override
  Scene build(DemoContext context) {
    final PostStage stage = PostStage.build(context);

    // #region lamp
    // Hung on the side the sun comes from, so the lit faces of the shapes turn
    // towards the glow: the lamp itself lights nothing.
    final MeshNode lamp = MeshNode(
      DeviceMesh.upload(
        context.device,
        const SphereShape(radius: 0.25, segments: 24, rings: 12).build(),
      ),
      RenderMaterial(
        name: 'lamp',
        baseColor: LinearColor.fromSrgb(0.1, 0.1, 0.1, 1.0),
        emissive: LinearColor(1.0, 0.85, 0.6),
        emissiveStrength: 9.0 * RenderMaterial.defaultEmissiveStrength,
      ),
      name: 'lamp',
    )..setPosition(1.0, 2.3, 0.7);
    // #endregion lamp

    return stage.scene..add(lamp);
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    bloom: BloomSettings(
      // #region glow
      threshold: threshold,
      intensity: intensity,
      // #endregion glow
      // #region reach
      levels: levels,
      // #endregion reach
      // #region halation
      halation: halation,
      // #endregion halation
    ),
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Threshold',
      min: 0,
      max: 4,
      value: () => threshold,
      onChanged: (double v) => threshold = v,
    ),
    SliderControl(
      'Intensity',
      min: 0,
      max: 1.5,
      value: () => intensity,
      onChanged: (double v) => intensity = v,
    ),
    SliderControl(
      'Reach (levels)',
      min: 1,
      max: 7,
      divisions: 6,
      value: () => levels.toDouble(),
      onChanged: (double v) => levels = v.round(),
      format: (double v) => '${v.round()}',
    ),
    SliderControl(
      'Halation',
      min: 0,
      max: 1,
      value: () => halation,
      onChanged: (double v) => halation = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (!passRan(frame, 'bloom')) {
      throw StateError('the bloom pass did not run: ${frame.skipped}');
    }
  }
}
