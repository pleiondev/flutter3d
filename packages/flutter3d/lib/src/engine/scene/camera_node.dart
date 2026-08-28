import 'package:vector_math/vector_math.dart';

import 'projection.dart';
import 'scene.dart';
import 'scene_node.dart';

/// A camera placed in the scene graph.
///
/// Being a node is the point: parenting a camera to a moving object is ordinary
/// hierarchy rather than a special "follow" feature, and the view matrix is just
/// the inverse of the node's world transform.
final class CameraNode extends SceneNode {
  CameraNode({Projection? projection, super.name})
    : projection = projection ?? const PerspectiveProjection();

  Projection projection;

  /// World-to-eye transform, recomputed only when the node moves.
  ///
  /// The view matrix is exactly the node's inverse world transform, so it reuses
  /// the cache every node has rather than keeping a second copy keyed on the
  /// same version.
  Matrix4 get viewMatrix => inverseWorldMatrix;

  /// Combined view-projection for a viewport of the given aspect ratio.
  ///
  /// Not cached: aspect changes with the viewport, and the multiply is cheap next
  /// to the per-draw work it feeds.
  Matrix4 viewProjection(double aspect) =>
      projection.toMatrix(aspect) * viewMatrix;

  /// World-space forward direction, the node's local -Z.
  ///
  /// Normalizes [out] in place and returns it, so the returned vector and [out]
  /// are the same object.
  Vector3 readForward([Vector3? out]) {
    final result = out ?? Vector3.zero();
    final m = worldMatrix.storage;
    result.setValues(-m[8], -m[9], -m[10]);
    if (result.length2 > 0.0) result.normalize();
    return result;
  }

  @override
  void onAttachedToScene(Scene scene) => scene.registerCamera(this);

  @override
  void onDetachedFromScene(Scene scene) => scene.unregisterCamera(this);
}
