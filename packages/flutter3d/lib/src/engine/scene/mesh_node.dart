import 'package:vector_math/vector_math.dart';

import '../geometry/mesh_geometry.dart';
import '../render/material.dart';
import 'scene.dart';
import 'scene_node.dart';
import 'skeleton.dart';

/// A node that draws a mesh.
///
/// The geometry is a [MeshGeometry] rather than a `GpuMesh`, which is what keeps
/// this whole layer free of the graphics backend: bounds, culling, framing and picking
/// need no device, and requiring one would mean none of them could be tested
/// without a GPU. The renderer is the place that cares whether the geometry has
/// actually been uploaded.
final class MeshNode extends SceneNode {
  MeshNode(this.mesh, this.material, {super.name});

  MeshGeometry mesh;
  Material material;

  /// The skeleton deforming this mesh, when it is skinned.
  ///
  /// Null for the overwhelming majority of meshes, and the renderer branches on
  /// it to pick the skinned vertex shader — the layout and the shader are one
  /// decision, so a mesh either has both or neither.
  Skeleton? skeleton;

  /// How far the surface reaches from its joints, **in the mesh's own units**.
  ///
  /// Used to pad the skinned bounds. Zero would cull a character by the box
  /// around its bones, clipping the mesh hanging off them; measured from the
  /// bind pose at instantiation, so it costs nothing per frame.
  ///
  /// The units are the trap, and they cost this repository an afternoon. A
  /// skinned mesh's vertex positions are in the rig's authoring space, which is
  /// a hundredth of a metre for both models here — so the radius measured off
  /// the buffer is a couple of centimetres for a body that reaches half a metre
  /// off the bone. Taken as metres it padded the bone box by nothing at all,
  /// and a monster you were standing next to blinked out whenever the camera
  /// turned. [Skeleton.skinScale] is what carries it out into the world, and
  /// [_refreshBounds] applies it.
  double skinReach = 0.0;

  /// Whether this node is drawn into the shadow map.
  ///
  /// Separate from [visible] because the two questions differ: a ground plane
  /// should receive shadows without casting one, and anything that follows the
  /// camera has no business in a light's view at all.
  bool castsShadow = true;

  /// Whether this caster never moves.
  ///
  /// A dungeon's walls do not, and their contribution to a point light's cube
  /// map can be rendered once at load instead of six times a frame. Everything
  /// else — a monster, a door, a pickup that spins — has to be redrawn, so the
  /// two are kept in separate maps and the shader takes whichever occluder is
  /// nearer.
  ///
  /// False by default, which is the safe way round: a mover wrongly marked
  /// static leaves its shadow behind when it moves, and that is a bug nobody
  /// looks for. A static thing wrongly left dynamic merely costs a redraw.
  bool shadowIsStatic = false;

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

  /// The skeleton pose the cached bounds were computed from, for skinned meshes.
  int _poseVersion = -1;
  MeshGeometry? _boundsMesh;

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
    final skin = skeleton;
    if (skin != null) {
      // A skinned mesh's own bounds describe the bind pose, which is not where
      // the animation has put it. The joints are, so cull against those.
      final stamp = skin.poseVersion;
      if (stamp == _poseVersion && mesh == _boundsMesh) return;
      _poseVersion = stamp;
      _boundsMesh = mesh;

      final bounds = skin.computeBounds(reach: skinReach * skin.skinScale);
      _worldBounds.min.setFrom(bounds.min);
      _worldBounds.max.setFrom(bounds.max);
      _boundsCentre
        ..setFrom(bounds.min)
        ..add(bounds.max)
        ..scale(0.5);
      _boundsRadius = ((bounds.max - bounds.min)..scale(0.5)).length;
      _mirrored = worldMatrix.determinant() < 0.0;
      return;
    }

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
