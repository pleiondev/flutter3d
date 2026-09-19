/// Finding which mesh a ray hits, entirely on the CPU: no frame, no readback,
/// an answer the moment it is asked.
///
/// Quoted by `raycast.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class RaycastDemo extends ShowcaseDemo {
  late final CameraNode _camera;
  late final Scene _scene;

  // #region raycaster
  final Raycaster _raycaster = Raycaster();
  // #endregion raycaster

  HitResult? lastHit;

  @override
  Scene build(DemoContext context) {
    _camera = context.camera;
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.7, 0.5, 0.4, 1.0),
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
    _scene = Scene()
      ..add(ball)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
    return _scene;
  }

  // #region cast
  void _castAtCentre() {
    _raycaster.setFromNdc(_camera, 0.0, 0.0, aspect: 16 / 9);
    lastHit = _raycaster.intersectScene(_scene);
  }
  // #endregion cast

  @override
  void update(DemoContext context, double dt) => _castAtCentre();

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // The ball sits on the camera's own axis, so a ray straight down the
    // middle of the screen has to find it.
    final HitResult? hit = lastHit;
    if (hit == null || hit.node?.name != 'ball') {
      throw StateError(
        'a ray through the centre of the screen missed the ball',
      );
    }
  }
}
