/// Asking the renderer which mesh is drawn at a point, by drawing the scene
/// once more as ids and reading one pixel back.
///
/// Quoted by `pixel_picking.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class PixelPickingDemo extends ShowcaseDemo {
  late final CameraNode _camera;
  final Raycaster _raycaster = Raycaster();

  /// What the last question answered, once the frame that drew the ids has
  /// come back. Null until then, and null again for a click on nothing.
  MeshNode? lastAnswer;

  @override
  Scene build(DemoContext context) {
    _camera = context.camera;
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.45, 0.6, 0.7, 1.0),
      roughness: 0.6,
    );
    final MeshNode ball = MeshNode(
      DeviceMesh.upload(
        context.device,
        SphereShape(segments: 32, rings: 16).build(),
      ),
      stone,
      name: 'ball',
    );
    return Scene()
      ..add(ball)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region pick
  void _pickCentre(DemoContext context) {
    context.renderer
        .pickPixel(0.5, 0.5)
        .then((MeshNode? node) => lastAnswer = node);
  }
  // #endregion pick

  @override
  void update(DemoContext context, double dt) => _pickCentre(context);

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // pickPixel answers a frame or two after it is asked, on a completer this
    // page does not block on. The honest, synchronous half of the claim is
    // that (0.5, 0.5), the middle of the frame, really is over the mesh the
    // id pass would find there. A raycaster through the same point checks
    // exactly that, with no frame involved.
    final HitResult? hit = _raycaster
        .setFromNdc(_camera, 0.0, 0.0, aspect: 16 / 9)
        .intersectScene(scene);
    if (hit?.node?.name != 'ball') {
      throw StateError('the pixel asked about is not over the ball');
    }
  }
}
