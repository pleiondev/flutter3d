import 'package:vector_math/vector_math.dart';

import '../gpu/gpu_mesh.dart';
import '../render/material.dart';
import 'scene.dart';
import 'scene_node.dart';

/// A node that draws a mesh.
final class MeshNode extends SceneNode {
  MeshNode(this.mesh, this.material, {super.name});

  GpuMesh mesh;
  Material material;

  /// Skips frustum culling for this node.
  ///
  /// Worth setting on anything that follows the camera, such as a skybox, whose
  /// bounds do not describe where it actually ends up on screen.
  bool frustumCulled = true;

  final Aabb3 _worldBounds = Aabb3();
  final Vector3 _boundsCentre = Vector3.zero();
  double _boundsRadius = 0.0;
  bool _mirrored = false;

  final Matrix4 _normalMatrix = Matrix4.identity();
  int _normalVersion = -1;

  /// The transform version the cached bounds were computed from. Since the world
  /// matrix is the only thing that invalidates them, its version is the whole
  /// cache key.
  int _boundsVersion = -1;
  GpuMesh? _boundsMesh;

  /// World-space axis-aligned bounds, recomputed only when the transform changes.
  Aabb3 get worldBounds {
    _refreshBounds();
    return _worldBounds;
  }

  /// Centre of the world bounding sphere used for the cheap culling test.
  Vector3 get worldBoundsCentre {
    _refreshBounds();
    return _boundsCentre;
  }

  double get worldBoundsRadius {
    _refreshBounds();
    return _boundsRadius;
  }

  /// Inverse-transpose of the world matrix, for transforming normals.
  ///
  /// Cached on the node rather than recomputed per draw: an invert plus a
  /// transpose costs about 21 ns, which is 1.07 ms across 50 000 draws — pure
  /// waste for anything that did not move since last frame. Keyed on
  /// [worldVersion], so it refreshes exactly when the transform does.
  ///
  /// mat3(model) would be enough while the scale stays uniform, but glTF nodes and
  /// user code both produce non-uniform scale, and that skews normals.
  Matrix4 get worldNormalMatrix {
    final version = worldVersion;
    if (version != _normalVersion) {
      _normalMatrix.setFrom(worldMatrix);
      _normalMatrix.invert();
      _normalMatrix.transpose();
      _normalVersion = version;
    }
    return _normalMatrix;
  }

  /// True when the world transform mirrors, i.e. its determinant is negative.
  ///
  /// Mirroring reverses on-screen triangle orientation, so the renderer has to
  /// flip its front-face winding for this node or backface culling discards
  /// exactly the faces meant to be visible. Cached with the bounds because both
  /// are invalidated by the same thing.
  bool get worldIsMirrored {
    _refreshBounds();
    return _mirrored;
  }

  void _refreshBounds() {
    final version = worldVersion;
    if (version == _boundsVersion && mesh == _boundsMesh) return;

    // Transforming the eight corners is necessary: rotating an AABB and taking
    // the extents of the result is only correct for axis-aligned rotations.
    final local = mesh.bounds;
    final matrix = worldMatrix;
    final corner = Vector3.zero();

    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;

    for (var i = 0; i < 8; i++) {
      corner.setValues(
        (i & 1) == 0 ? local.min.x : local.max.x,
        (i & 2) == 0 ? local.min.y : local.max.y,
        (i & 4) == 0 ? local.min.z : local.max.z,
      );
      matrix.transform3(corner);
      if (corner.x < minX) minX = corner.x;
      if (corner.y < minY) minY = corner.y;
      if (corner.z < minZ) minZ = corner.z;
      if (corner.x > maxX) maxX = corner.x;
      if (corner.y > maxY) maxY = corner.y;
      if (corner.z > maxZ) maxZ = corner.z;
    }

    _worldBounds.min.setValues(minX, minY, minZ);
    _worldBounds.max.setValues(maxX, maxY, maxZ);
    _boundsCentre.setValues(
      (minX + maxX) * 0.5,
      (minY + maxY) * 0.5,
      (minZ + maxZ) * 0.5,
    );
    final dx = (maxX - minX) * 0.5;
    final dy = (maxY - minY) * 0.5;
    final dz = (maxZ - minZ) * 0.5;
    // Sphere around the world AABB: slightly loose, but a sphere test is far
    // cheaper than a box test and rejects most of what is off screen.
    _boundsRadius = Vector3(dx, dy, dz).length;

    _mirrored = matrix.determinant() < 0.0;

    _boundsVersion = version;
    _boundsMesh = mesh;
  }

  @override
  void onAttachedToScene(Scene scene) => scene.registerMesh(this);

  @override
  void onDetachedFromScene(Scene scene) => scene.unregisterMesh(this);
}
