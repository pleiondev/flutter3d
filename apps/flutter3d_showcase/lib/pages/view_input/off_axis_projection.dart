/// A frustum whose axis is not down the middle of the view: what a headset
/// lens or a portal window needs instead of an ordinary field of view.
///
/// Quoted by `off_axis_projection.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class OffAxisProjectionDemo extends ShowcaseDemo {
  double shift = 0.5;

  late OffAxisProjection _off;

  @override
  Scene build(DemoContext context) {
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.68, 0.72, 0.78, 1.0),
      roughness: 0.7,
    );
    final MeshNode ball = MeshNode(
      DeviceMesh.upload(
        context.device,
        SphereShape(segments: 32, rings: 16).build(),
      ),
      stone,
      name: 'ball',
    );

    // #region symmetric
    final OffAxisProjection symmetric = OffAxisProjection.symmetric(
      fovYRadians: 0.9,
      aspect: 16 / 9,
    );
    // #endregion symmetric

    // #region skew
    _off = symmetric.copyWith(
      tanLeft: symmetric.tanLeft - shift,
      tanRight: symmetric.tanRight - shift,
    );
    // #endregion skew
    context.camera.projection = _off;

    return Scene()
      ..add(ball)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.3, -1.0, -0.4)),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    final OffAxisProjection symmetric = OffAxisProjection.symmetric(
      fovYRadians: 0.9,
      aspect: 16 / 9,
    );
    _off = symmetric.copyWith(
      tanLeft: symmetric.tanLeft - shift,
      tanRight: symmetric.tanRight - shift,
    );
    context.camera.projection = _off;
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Shift',
      min: -0.6,
      max: 0.6,
      value: () => shift,
      onChanged: (double v) => shift = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // The off-centre term in column 2 of the matrix is what shears the
    // frustum. It is zero only when the frustum is symmetric: away from
    // shift == 0 it must be non-zero, or the shift did nothing.
    final Matrix4 matrix = _off.toMatrix(16 / 9);
    final double offCentre = matrix.storage[8];
    if (shift != 0.0 && offCentre == 0.0) {
      throw StateError('a shifted frustum should not be symmetric');
    }
  }
}
