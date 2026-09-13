/// The per-node and per-triangle intersection tests, and the code that fills
/// [HitResult] from them.
///
/// **A part of `raycaster.dart`, not a file of its own.** These are
/// [Raycaster]'s methods, reading and writing its private scratch fields
/// (`_a`, `_b`, `_c`, `_bary`, `_localRay`, `_hit`) that exist purely to avoid
/// allocating a `Vector3` per triangle in what is a hot loop on every pointer
/// move during picking. Making those public just to split the file would cost
/// the thing they are there for.
part of 'raycaster.dart';

/// Triangle- and box-level hit testing, kept apart from [Raycaster]'s public
/// setup and scene-traversal API above.
extension _RaycasterHitTests on Raycaster {
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
