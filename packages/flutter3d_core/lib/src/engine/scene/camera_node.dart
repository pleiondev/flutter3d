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

  /// Where the rays this camera draws begin, in world space, written into
  /// [out] and returned — what the renderer measures every eye-relative
  /// quantity from: depths in the surface buffer, the fog's air, the shadow
  /// cascades' splits.
  ///
  /// The camera's own position, except through an orthographic lens whose
  /// near plane is behind it — `P7`. There the rays start on that plane, and
  /// what stands between it and the camera is drawn; measured from the
  /// camera it had a depth of nought or less, which the surface buffer reads
  /// as sky, and no fog in front of it. Through an orthographic lens the
  /// camera's place along its axis moves nothing in the picture, so moving
  /// the origin back to the plane changes nothing but the measurements.
  Vector3 readViewOrigin([Vector3? out]) {
    final result = readWorldPosition(out);
    final lens = projection;
    if (lens is OrthographicProjection && lens.near < 0.0) {
      final forward = readForward();
      result.addScaled(forward, lens.near);
    }
    return result;
  }

  @override
  void onAttachedToScene(Scene scene) => scene.registerCamera(this);

  @override
  void onDetachedFromScene(Scene scene) => scene.unregisterCamera(this);
}
