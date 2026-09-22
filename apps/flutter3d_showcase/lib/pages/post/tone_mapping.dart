/// The curve that squeezes light of any brightness into a picture a display can
/// show, and five of them side by side.
///
/// Quoted by `tone_mapping.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ToneMappingDemo extends ShowcaseDemo {
  int curve = 0;
  double exposure = 1.6;

  static const List<TonemapCurve> _curves = TonemapCurve.values;

  @override
  void configureView(DemoContext context) =>
      PostStage.frame(context, distance: 7.0);

  @override
  Scene build(DemoContext context) {
    final PostStage stage = PostStage.build(context, sunIntensity: 6.0);

    // #region lamps
    final DeviceMesh ball = DeviceMesh.upload(
      context.device,
      const SphereShape(radius: 0.28, segments: 24, rings: 12).build(),
    );
    const List<List<double>> colours = <List<double>>[
      <double>[1.0, 0.1, 0.05],
      <double>[0.1, 0.9, 0.2],
      <double>[0.1, 0.25, 1.0],
    ];
    for (var i = 0; i < colours.length; i++) {
      stage.scene.add(
        MeshNode(
          ball,
          Material(
            name: 'lamp $i',
            baseColor: Vector4(0.05, 0.05, 0.05, 1.0),
            emissive: Vector3(colours[i][0], colours[i][1], colours[i][2]),
            emissiveStrength: 6.0,
          ),
          name: 'lamp $i',
        )..setPosition((i - 1) * 1.1, 1.7, -1.4),
      );
    }
    // #endregion lamps

    return stage.scene;
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region exposure
    exposure: exposure,
    // #endregion exposure
    // #region curve
    tonemapCurve: _curves[curve],
    // #endregion curve
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Curve',
      options: <String>[for (final TonemapCurve c in _curves) c.name],
      index: () => curve,
      onChanged: (int i) => curve = i,
    ),
    SliderControl(
      'Exposure',
      min: 0.2,
      max: 6,
      value: () => exposure,
      onChanged: (double v) => exposure = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (!passRan(frame, 'composite')) {
      throw StateError(
        'the composite pass, which applies the curve, is absent',
      );
    }
    if ((frame.exposure - exposure).abs() > 1e-6) {
      throw StateError('the frame was exposed at ${frame.exposure}');
    }
  }
}
