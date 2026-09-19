/// `RenderSettings.exposure`: the linear multiplier the composite applies
/// before the tone curve, set by hand rather than metered.
///
/// Quoted by `exposure.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ExposureDemo extends ShowcaseDemo {
  double exposure = 2.4;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.0
      ..pitch = 0.1;
  }

  @override
  Scene build(DemoContext context) {
    // #region scene
    final Material lantern = Material(
      name: 'lantern',
      baseColor: Vector4(0.9, 0.85, 0.6, 1.0),
      emissive: Vector3(2.0, 1.7, 0.9),
    );
    final MeshNode box = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(1.4, 1.4, 1.4)).build(),
      ),
      lantern,
      name: 'lantern',
    );
    return Scene()
      ..add(box)
      ..add(
        LightNode(name: 'sun', intensity: 1.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.7)),
      );
    // #endregion scene
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    exposure: exposure,
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Exposure',
      min: 0.1,
      max: 4,
      value: () => exposure,
      onChanged: (double v) => exposure = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if ((frame.exposure - exposure).abs() > 1e-6) {
      throw StateError(
        'the frame was composited at ${frame.exposure}, not the '
        '$exposure this page asked for',
      );
    }
    if (frame.drawCalls < 1) {
      throw StateError('the lantern was not drawn');
    }
    // #endregion check
  }
}
