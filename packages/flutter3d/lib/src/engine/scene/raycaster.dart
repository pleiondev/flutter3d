import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' hide Ray;

import '../geometry/mesh_data.dart';
import '../geometry/vertex_layout.dart';
import '../math/intersections.dart';
import 'bvh.dart';
import 'camera_node.dart';
import 'mesh_node.dart';
import 'scene.dart';
import 'scene_spheres.dart';

part 'raycaster_hit_tests.dart';

/// What a ray hit.
///
/// Mutable and reused by [Raycaster]: picking runs on pointer events, and a
/// fresh result object per candidate mesh is the allocation pattern this engine
/// avoids everywhere else.
final class HitResult {
  MeshNode? node;

  /// Distance along the ray, in world units.
  double distance = 0.0;

  /// Where the ray met the surface, in world space.
  final Vector3 point = Vector3.zero();

  /// Surface normal at the hit, in world space, unit length.
  ///
  /// Interpolated from the triangle's vertex normals when the mesh has them, so
  /// a smooth-shaded sphere reports a smoothly varying normal rather than the
  /// facet's. Falls back to the geometric normal otherwise.
  final Vector3 normal = Vector3.zero();

  /// Texture coordinate at the hit, zero when the mesh carries none.
  final Vector2 uv = Vector2.zero();

  /// Index of the triangle that was hit, or `-1` for an approximate hit.
  int triangleIndex = -1;

  /// True when the mesh had no CPU-side geometry and the hit is against its
  /// bounding box instead.
  ///
  /// Worth surfacing rather than hiding: a caller placing a decal at the hit
  /// point needs to know the point is on a box, not on the surface.
  bool approximate = false;

  MeshNode get requireNode => node!;

  void _reset() {
    node = null;
    distance = double.infinity;
    triangleIndex = -1;
    approximate = false;
    point.setZero();
    normal.setZero();
    uv.setZero();
  }

  @override
  String toString() =>
      'HitResult(${node?.name ?? 'none'} at $distance, '
      'triangle $triangleIndex${approximate ? ', approximate' : ''})';
}

/// Casts rays against a [Scene] on the CPU.
///
/// Pure maths on top of the scene graph and the geometry layer, with no GPU
/// involvement — which is both what makes it testable without a device and the
/// only option available on the backend this was written against, which exposes
/// neither compute nor buffer
/// readback.
///
/// The traversal is deliberately the same shape as culling: a linear pass over
/// the scene's flat mesh registry, rejecting on the cached world bounding sphere
/// before touching a single triangle. A spatial index replaces that first pass
/// later without changing anything below it.
final class Raycaster {
  Raycaster();

  /// The ray being cast, in world space.
  final Ray ray = Ray.zero();

  /// Maximum distance to consider. Anything further away is a miss.
  double maxDistance = double.infinity;

  /// Whether to ignore triangles facing away from the ray.
  ///
  /// Off by default: picking should find a surface the user can see, and a
  /// double-sided or inside-out mesh is still something they clicked on.
  bool cullBackFaces = false;

  /// Optional spatial index, normally the render list's.
  ///
  /// Shared rather than owned: the renderer already rebuilds a tree over the
  /// same meshes every frame, and a second one would double both the memory and
  /// the rebuild cost to answer the same question.
  SceneBvh? bvh;

  /// Above this many meshes a tree is worth using, matching the render list's
  /// threshold so a scene does not end up with one consumer on each path.
  static const int bvhThreshold = 512;

  Float32List _spheres = Float32List(0);

  final HitResult _hit = HitResult();
  final Ray _localRay = Ray.zero();
  final Vector3 _a = Vector3.zero();
  final Vector3 _b = Vector3.zero();
  final Vector3 _c = Vector3.zero();
  final Vector2 _bary = Vector2.zero();
  final Matrix4 _inverseViewProjection = Matrix4.identity();
  final Vector3 _nearPoint = Vector3.zero();
  final Vector3 _farPoint = Vector3.zero();

  /// Aims the ray through a point in normalized device coordinates.
  ///
  /// NDC is `x` and `y` in `[-1, 1]` with **+Y up**, and depth in `[0, 1]` as
  /// every projection in this engine produces. The ray is built by unprojecting
  /// the near and far points of that NDC column, which is the one construction
  /// that works for perspective and orthographic cameras alike — an orthographic
  /// ray does not pass through the camera's position at all.
  Raycaster setFromNdc(
    CameraNode camera,
    double ndcX,
    double ndcY, {
    required double aspect,
  }) {
    _inverseViewProjection.setFrom(camera.viewProjection(aspect));
    _inverseViewProjection.invert();

    _nearPoint.setValues(ndcX, ndcY, 0.0);
    _farPoint.setValues(ndcX, ndcY, 1.0);
    _inverseViewProjection.perspectiveTransform(_nearPoint);
    _inverseViewProjection.perspectiveTransform(_farPoint);

    ray.origin.setFrom(_nearPoint);
    ray.direction
      ..setFrom(_farPoint)
      ..sub(_nearPoint);
    ray.normalizeDirection();
    return this;
  }

  /// Aims the ray through a point in widget coordinates.
  ///
  /// [x] and [y] are measured from the top-left, the way Flutter reports a
  /// pointer position, in the same units as [width] and [height]. Keeping the
  /// conversion here rather than at the call site is worth it: the Y flip and
  /// the aspect ratio are exactly the two things that get silently reversed.
  Raycaster setFromScreen(
    CameraNode camera,
    double x,
    double y, {
    required double width,
    required double height,
  }) {
    if (width <= 0.0 || height <= 0.0) {
      throw ArgumentError(
        'Viewport must have a positive size, got '
        '${width}x$height.',
      );
    }
    return setFromNdc(
      camera,
      (x / width) * 2.0 - 1.0,
      1.0 - (y / height) * 2.0,
      aspect: width / height,
    );
  }

  /// The nearest mesh the ray hits, or null.
  ///
  /// The returned object is reused by the next call; copy anything that has to
  /// outlive it.
  HitResult? intersectScene(
    Scene scene, {
    int layerMask = ~0,
    bool visibleOnly = true,
  }) {
    _hit._reset();
    var best = maxDistance;

    final meshes = scene.meshes;

    /// One candidate, whichever way it arrived.
    ///
    /// The tree may only skip meshes the ray provably misses, so everything it
    /// does produce runs the same tests the linear pass would — which is what
    /// keeps the two paths returning the same hit.
    void consider(MeshNode node) {
      if (visibleOnly && !node.visibleInHierarchy) return;
      if ((node.layerMask & layerMask) == 0) return;
      if (node.mesh.indexCount == 0) return;

      // The same cheap rejection culling uses, against the same cached sphere.
      final sphereDistance = raySphere(
        ray,
        node.worldBoundsCentre,
        node.worldBoundsRadius,
      );
      if (sphereDistance == kNoHit || sphereDistance > best) return;

      if (_intersectNode(node, best)) best = _hit.distance;
    }

    final tree = bvh;
    if (tree != null && meshes.length >= bvhThreshold) {
      _spheres = ensureSphereCapacity(_spheres, meshes.length);
      tree.refresh(_spheres, meshes.length, packSceneSpheres(meshes, _spheres));
      // maxDistance, not `best`: the closure narrows `best` as it goes, but the
      // traversal order is not front-to-back, so a node rejected on a stale
      // bound could be the nearest hit.
      tree.queryRay(
        ray,
        (index) => consider(meshes[index]),
        maxDistance: maxDistance,
      );
    } else {
      for (var i = 0; i < meshes.length; i++) {
        consider(meshes[i]);
      }
    }

    return _hit.node == null ? null : _hit;
  }
}
