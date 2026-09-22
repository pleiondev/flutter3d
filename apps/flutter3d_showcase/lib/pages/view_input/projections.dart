/// Two ways to turn a scene into a flat picture: perspective, where things
/// shrink with distance, and orthographic, where they do not.
///
/// Quoted by `projections.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ProjectionsDemo extends ShowcaseDemo {
  int choice = 0;

  late Projection _projection;

  @override
  Scene build(DemoContext context) {
    // #region box
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.7, 0.68, 0.64, 1.0),
      roughness: 0.8,
    );
    final MeshNode box = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3.all(1.4)).build(),
      ),
      stone,
      name: 'box',
    );
    // #endregion box

    // #region perspective
    _projection = const PerspectiveProjection(fovYRadians: 0.9);
    // #endregion perspective
    context.camera.projection = _projection;

    return Scene()
      ..add(box)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region orthographic
  void _choose(int value) {
    choice = value;
    _projection = value == 0
        ? const PerspectiveProjection(fovYRadians: 0.9)
        : const OrthographicProjection(height: 3.0);
  }
  // #endregion orthographic

  @override
  void update(DemoContext context, double dt) {
    context.camera.projection = _projection;
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Lens',
      options: const <String>['Perspective', 'Orthographic'],
      index: () => choice,
      onChanged: _choose,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the box was not drawn');
    }
    // A perspective matrix divides by depth: row 3 sends w to -z, so the
    // bottom-right entry of the 4x4 is 0. An orthographic one does not: a
    // point at any depth keeps w = 1, so that entry is 1. This is the one
    // number that tells the two matrices apart.
    final Matrix4 matrix = _projection.toMatrix(16 / 9);
    final double bottomRight = matrix.storage[15];
    final bool isOrthographic = _projection is OrthographicProjection;
    if (isOrthographic && bottomRight != 1.0) {
      throw StateError('an orthographic matrix should keep w at 1');
    }
    if (!isOrthographic && bottomRight != 0.0) {
      throw StateError('a perspective matrix should not keep w at 1');
    }
  }
}
