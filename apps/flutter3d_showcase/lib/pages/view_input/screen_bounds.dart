/// Where a box in the world lands on the glass, as a rectangle a focus ring
/// or a label can use.
///
/// Quoted by `screen_bounds.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ScreenBoundsDemo extends ShowcaseDemo {
  late final CameraNode _camera;
  late final Aabb3 _box;
  ScreenBounds? _bounds;

  @override
  Scene build(DemoContext context) {
    _camera = context.camera;
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.55, 0.68, 0.5, 1.0),
      roughness: 0.7,
    );
    // #region box
    _box = Aabb3.centerAndHalfExtents(Vector3.zero(), Vector3(0.6, 0.6, 0.6));
    // #endregion box
    final MeshNode cube = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3.all(1.2)).build(),
      ),
      stone,
      name: 'cube',
    );
    return Scene()
      ..add(cube)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region bounds
  void _measure(DemoContext context) {
    final Matrix4 viewProjection = _camera.viewProjection(320 / 180);
    _bounds = screenBoundsOfBox(viewProjection, _box, width: 320, height: 180);
  }
  // #endregion bounds

  @override
  void update(DemoContext context, double dt) => _measure(context);

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the cube was not drawn');
    }
    final ScreenBounds? bounds = _bounds;
    if (bounds == null) {
      throw StateError('the cube is behind the camera or the box is wrong');
    }
    // The rectangle screenBoundsOfBox answers has to be a real rectangle:
    // its left edge left of its right edge, its top above its bottom, and
    // the whole of it somewhere the 320x180 frame could actually show.
    if (bounds.left >= bounds.right || bounds.top >= bounds.bottom) {
      throw StateError('screenBoundsOfBox returned a degenerate rectangle');
    }
    // The cube sits on the camera's own axis, at the middle of the screen,
    // so the rectangle it projects to has to contain the middle of the
    // frame.
    const double centreX = 160.0;
    const double centreY = 90.0;
    if (centreX < bounds.left ||
        centreX > bounds.right ||
        centreY < bounds.top ||
        centreY > bounds.bottom) {
      throw StateError(
        'the cube in the middle of the view missed the middle of its own rectangle',
      );
    }
  }
}
