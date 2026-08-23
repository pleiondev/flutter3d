import 'dart:math' as math;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import 'scene.dart';
import 'scene_node.dart';

/// How a camera maps eye space onto clip space.
///
/// The matrix maths lives inside each implementation rather than in free
/// functions the implementations call: the depth convention is the thing most
/// easily got wrong, and keeping it in one polymorphic place means there is no
/// second copy to drift.
///
/// Every implementation targets a `[0, 1]` NDC depth range, which is the Metal
/// and Vulkan convention rather than OpenGL's `[-1, 1]`. Feeding an OpenGL-style
/// matrix to a device expecting this one puts roughly half the view volume
/// behind the near plane, so the model looks half-eaten or vanishes — with no
/// error reported.
///
/// The device is asked which it wants; see [toDepthRange] and
/// `GraphicsDevice.depthRange`.
///
/// Y is deliberately not flipped. Metal NDC has +Y up while its framebuffer
/// origin is top-left, which already places row 0 at the top of the texture.
/// Negating Y would mirror the image and, because mirroring reverses triangle
/// orientation on screen, make backface culling discard exactly the faces meant
/// to be visible.
sealed class Projection {
  const Projection();

  /// Builds the projection matrix for a given viewport aspect ratio.
  Matrix4 toMatrix(double aspect);

  double get near;
  double get far;

  /// Projects an eye-space point to NDC.
  ///
  /// The only honest way to assert what a projection actually does, which is why
  /// it lives on the abstraction rather than in test-only code.
  Vector3 projectToNdc(Vector3 eyePosition, {double aspect = 1.0}) {
    final clip = toMatrix(aspect).transform(
      Vector4(eyePosition.x, eyePosition.y, eyePosition.z, 1.0),
    );
    if (clip.w == 0.0) {
      throw ArgumentError('Point projects onto the camera plane (w == 0).');
    }
    return Vector3(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w);
  }
}

final class PerspectiveProjection extends Projection {
  const PerspectiveProjection({
    this.fovYRadians = math.pi / 4,
    this.near = 0.1,
    this.far = 1000.0,
  });

  /// Vertical field of view. Vertical rather than horizontal so that widening the
  /// viewport reveals more scene instead of squashing it.
  final double fovYRadians;

  @override
  final double near;

  @override
  final double far;

  @override
  Matrix4 toMatrix(double aspect) {
    if (aspect <= 0.0) {
      throw ArgumentError('aspect must be > 0, got $aspect.');
    }
    if (near <= 0.0 || far <= near) {
      throw ArgumentError('Expected 0 < near < far, got near=$near far=$far.');
    }

    final f = 1.0 / math.tan(fovYRadians / 2.0);
    final m = Matrix4.zero();

    // setEntry takes (row, column). The two depth terms below sit in different
    // rows and are easy to transpose by accident; swapping them yields a matrix
    // that maps everything outside the clip volume, i.e. a black viewport with no
    // error anywhere. projection_test.dart pins the mapping.
    m.setEntry(0, 0, f / aspect);
    m.setEntry(1, 1, f);
    m.setEntry(2, 2, far / (near - far));
    m.setEntry(2, 3, (near * far) / (near - far));
    m.setEntry(3, 2, -1.0);

    return m;
  }

  PerspectiveProjection copyWith({
    double? fovYRadians,
    double? near,
    double? far,
  }) =>
      PerspectiveProjection(
        fovYRadians: fovYRadians ?? this.fovYRadians,
        near: near ?? this.near,
        far: far ?? this.far,
      );
}

final class OrthographicProjection extends Projection {
  const OrthographicProjection({
    this.height = 2.0,
    this.near = 0.1,
    this.far = 1000.0,
  });

  /// Vertical extent of the view volume in world units; width follows the aspect.
  final double height;

  @override
  final double near;

  @override
  final double far;

  @override
  Matrix4 toMatrix(double aspect) {
    if (aspect <= 0.0) {
      throw ArgumentError('aspect must be > 0, got $aspect.');
    }
    if (height <= 0.0 || near == far) {
      throw ArgumentError(
        'Degenerate orthographic volume: height=$height near=$near far=$far.',
      );
    }

    final halfHeight = height * 0.5;
    final halfWidth = halfHeight * aspect;

    final m = Matrix4.zero();
    m.setEntry(0, 0, 1.0 / halfWidth);
    m.setEntry(1, 1, 1.0 / halfHeight);
    // Depth maps near -> 0 and far -> 1 for an eye space looking down -Z.
    m.setEntry(2, 2, 1.0 / (near - far));
    m.setEntry(2, 3, near / (near - far));
    m.setEntry(3, 3, 1.0);
    return m;
  }

  OrthographicProjection copyWith({
    double? height,
    double? near,
    double? far,
  }) =>
      OrthographicProjection(
        height: height ?? this.height,
        near: near ?? this.near,
        far: far ?? this.far,
      );
}

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


/// [projection] expressed for [range].
///
/// Cameras here build for [DepthRange.zeroToOne] — the Metal and Vulkan
/// convention — and this is the one place that changes. Doubling the depth row
/// and subtracting w turns near-at-0/far-at-1 into near-at-minus-one/far-at-1,
/// which is what OpenGL and WebGL clip against.
///
/// A function rather than a branch inside the renderer, so it can be checked
/// without a device. The failure it prevents is not a crash: an uncorrected
/// matrix on GL draws every object, in the right order, inside the far half of
/// the depth buffer. Half the precision, nothing reported anywhere, and
/// z-fighting on surfaces that were fine on the other backend.
Matrix4 toDepthRange(Matrix4 projection, DepthRange range) {
  if (range == DepthRange.zeroToOne) return projection;
  return Matrix4.identity()
    ..setEntry(2, 2, 2.0)
    ..setEntry(2, 3, -1.0)
    ..multiply(projection);
}


/// [projection] adjusted for where [origin] puts row zero.
///
/// For sampling a texture the engine rendered, not for drawing into one. A
/// shader that looks into a shadow map turns clip space into a uv, and that
/// conversion assumes row zero is at the top — which is true of the texture on
/// a top-left backend and false on a bottom-left one, where the same geometry
/// lands mirrored in memory.
///
/// Negating y in the matrix the *shader* is given produces the mirrored uv
/// without the shader knowing which backend it is on. Doing it here rather than
/// in GLSL keeps one shader for both and keeps the convention in the one place
/// that already knows it.
///
/// Not to be confused with negating y in a matrix used for *drawing*, which
/// would mirror the picture and reverse triangle orientation with it.
Matrix4 toFramebufferOrigin(Matrix4 projection, FramebufferOrigin origin) {
  if (origin == FramebufferOrigin.topLeft) return projection;
  return Matrix4.identity()
    ..setEntry(1, 1, -1.0)
    ..multiply(projection);
}
