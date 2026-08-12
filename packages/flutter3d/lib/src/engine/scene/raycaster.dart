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
  String toString() => 'HitResult(${node?.name ?? 'none'} at $distance, '
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
  Raycaster setFromNdc(CameraNode camera, double ndcX, double ndcY,
      {required double aspect}) {
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
      throw ArgumentError('Viewport must have a positive size, got '
          '${width}x$height.');
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
      tree.refresh(
        _spheres,
        meshes.length,
        packSceneSpheres(meshes, _spheres),
      );
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

  /// Tests one node, writing into [_hit] when it beats [best].
  bool _intersectNode(MeshNode node, double best) {
    // Into the mesh's own space: one matrix applied to the ray instead of a
    // matrix applied to every vertex. Scale makes the local direction
    // non-unit, which is exactly right — it keeps t measured in world units.
    ray.transformInto(node.inverseWorldMatrix, _localRay);

    final source = node.mesh.source;
    if (source == null) {
      // No CPU geometry: the bounding box is the best answer available, and
      // saying so beats reporting nothing or pretending it is exact.
      final t = rayAabb(_localRay, node.mesh.bounds);
      if (t == kNoHit || t >= best) return false;
      _writeApproximateHit(node, t);
      return true;
    }

    // A box test in local space rejects the common near-miss, where the sphere
    // was hit but the mesh inside it was not.
    if (rayAabb(_localRay, node.mesh.bounds) == kNoHit) return false;

    return _intersectTriangles(node, source, best);
  }

  bool _intersectTriangles(MeshNode node, MeshData mesh, double best) {
    final indices = mesh.indices;
    final stride = mesh.layout.floatsPerVertex;
    final vertices = mesh.vertices;

    var nearest = best;
    var nearestTriangle = -1;
    var nearestU = 0.0;
    var nearestV = 0.0;

    for (var i = 0; i + 2 < indices.length; i += 3) {
      final ia = indices[i] * stride;
      final ib = indices[i + 1] * stride;
      final ic = indices[i + 2] * stride;

      _a.setValues(vertices[ia], vertices[ia + 1], vertices[ia + 2]);
      _b.setValues(vertices[ib], vertices[ib + 1], vertices[ib + 2]);
      _c.setValues(vertices[ic], vertices[ic + 1], vertices[ic + 2]);

      final t = rayTriangle(
        _localRay,
        _a,
        _b,
        _c,
        outUv: _bary,
        cullBackFace: cullBackFaces,
      );
      if (t == kNoHit || t >= nearest) continue;

      nearest = t;
      nearestTriangle = i ~/ 3;
      nearestU = _bary.x;
      nearestV = _bary.y;
    }

    if (nearestTriangle < 0) return false;

    _writeTriangleHit(node, mesh, nearestTriangle, nearest, nearestU, nearestV);
    return true;
  }

  void _writeApproximateHit(MeshNode node, double t) {
    _hit
      ..node = node
      ..distance = t
      ..triangleIndex = -1
      ..approximate = true;
    ray.pointAt(t, _hit.point);
    // The box face is not known here, so the only honest normal points back
    // along the ray.
    _hit.normal
      ..setFrom(ray.direction)
      ..negate();
    if (_hit.normal.length2 > 0.0) _hit.normal.normalize();
    _hit.uv.setZero();
  }

  void _writeTriangleHit(
    MeshNode node,
    MeshData mesh,
    int triangle,
    double t,
    double u,
    double v,
  ) {
    _hit
      ..node = node
      ..distance = t
      ..triangleIndex = triangle
      ..approximate = false;
    ray.pointAt(t, _hit.point);

    final layout = mesh.layout;
    final stride = layout.floatsPerVertex;
    final vertices = mesh.vertices;
    final base = triangle * 3;
    final ia = mesh.indices[base] * stride;
    final ib = mesh.indices[base + 1] * stride;
    final ic = mesh.indices[base + 2] * stride;

    final w = 1.0 - u - v;

    final normalOffset = layout.floatOffsetOf(VertexLayout.normal.name);
    if (normalOffset >= 0) {
      _hit.normal.setValues(
        vertices[ia + normalOffset] * w +
            vertices[ib + normalOffset] * u +
            vertices[ic + normalOffset] * v,
        vertices[ia + normalOffset + 1] * w +
            vertices[ib + normalOffset + 1] * u +
            vertices[ic + normalOffset + 1] * v,
        vertices[ia + normalOffset + 2] * w +
            vertices[ib + normalOffset + 2] * u +
            vertices[ic + normalOffset + 2] * v,
      );
    } else {
      // Geometric normal from the winding, for geometry with no normals.
      _a.setValues(vertices[ia], vertices[ia + 1], vertices[ia + 2]);
      _b.setValues(vertices[ib], vertices[ib + 1], vertices[ib + 2]);
      _c.setValues(vertices[ic], vertices[ic + 1], vertices[ic + 2]);
      _b.sub(_a);
      _c.sub(_a);
      _b.crossInto(_c, _hit.normal);
    }

    // The inverse transpose, not the world matrix: under non-uniform scale the
    // two differ, and using the wrong one tilts every normal the pick reports.
    node.worldNormalMatrix.rotate3(_hit.normal);
    if (_hit.normal.length2 > 0.0) {
      _hit.normal.normalize();
    } else {
      _hit.normal
        ..setFrom(ray.direction)
        ..negate()
        ..normalize();
    }

    final uvOffset = layout.floatOffsetOf(VertexLayout.texcoord.name);
    if (uvOffset >= 0) {
      _hit.uv.setValues(
        vertices[ia + uvOffset] * w +
            vertices[ib + uvOffset] * u +
            vertices[ic + uvOffset] * v,
        vertices[ia + uvOffset + 1] * w +
            vertices[ib + uvOffset + 1] * u +
            vertices[ic + uvOffset + 1] * v,
      );
    } else {
      _hit.uv.setZero();
    }
  }
}
