/// Bloom: the light that is brighter than the display spills over its edge.
///
/// Quoted by `bloom.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class BloomDemo extends ShowcaseDemo {
  double threshold = 1.0;
  double intensity = 0.35;
  double halation = 0.0;
  int levels = 5;

  @override
  void configureView(DemoContext context) => PostStage.frame(context);

  @override
  Scene build(DemoContext context) {
    final PostStage stage = PostStage.build(context);

    // #region lamp
    final MeshNode lamp = MeshNode(
      DeviceMesh.upload(
        context.device,
        const SphereShape(radius: 0.25, segments: 24, rings: 12).build(),
      ),
      Material(
        name: 'lamp',
        baseColor: Vector4(0.1, 0.1, 0.1, 1.0),
        emissive: Vector3(1.0, 0.85, 0.6),
        emissiveStrength: 9.0,
      ),
      name: 'lamp',
    )..setPosition(0.0, 1.6, -1.0);
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
