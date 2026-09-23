/// A skinned mesh's vertices where the skeleton actually has them —
/// `gfx-11n`'s own row.
///
/// **What this exists to fix.** The vertex stage poses a skinned mesh and the
/// CPU copy is the bind pose, so a raycast finds a character's arm where the
/// model was exported with it: a shot at a running figure misses, a click on
/// a raised arm selects nothing, and the bounding volumes — which *do* follow
/// the pose, through `MeshNode.skinReach` — only make the miss a candidate.
/// `Raycaster`'s own doc comment has described that for as long as it has
/// existed, with the cost of fixing it named: a posed copy of every skinned
/// mesh, per cast or per frame.
///
/// **This pays a smaller bill than the one that was quoted.** The copy is per
/// *node that a ray actually reaches*, not per skinned mesh in the scene —
/// the caster rejects on the world sphere and then on a local box before any
/// of this runs — and it is kept until the pose moves, so several casts
/// against a standing figure share one. A frame that casts nothing poses
/// nothing.
///
/// The arithmetic is the vertex stage's, in the same space: `mesh_skinned.vert`
/// builds `model * skin` and multiplies the local position by that, so the
/// skin half alone leaves the vertex in the mesh's own space — which is where
/// the caster has already put the ray.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
import 'package:vector_math/vector_math.dart';

import 'skeleton.dart';

/// Posed positions for one mesh and skeleton, reused while the pose holds.
final class PosedMesh {
  Float32List _positions = Float32List(0);
  int _vertexCount = 0;

  MeshData? _mesh;
  Skeleton? _skeleton;
  int _pose = -1;
  int _update = -1;

  /// Three floats a vertex, in the mesh's own space, or null when [mesh] is
  /// not skinned or [skeleton] cannot pose it.
  ///
  /// Reads [Skeleton.matrices] as they stand, so the caller brings them up to
  /// date first with [Skeleton.update] for the node being tested.
  ///
  /// Recomputed only when the mesh, the skeleton or its matrices have changed
  /// — identity for the first two, and for the third [Skeleton.poseVersion]
  /// together with [Skeleton.updateCount]. The pose stamp alone is not enough:
  /// two nodes sharing a skeleton at different transforms leave it with one
  /// pose and two sets of matrices in turn.
  Float32List? positionsOf(MeshData mesh, Skeleton skeleton) {
    if (!mesh.layout.isSkinned) return null;
    if (skeleton.jointCount == 0) return null;

    if (identical(_mesh, mesh) &&
        identical(_skeleton, skeleton) &&
        _pose == skeleton.poseVersion &&
        _update == skeleton.updateCount) {
      return _positions;
    }

    final stride = mesh.layout.floatsPerVertex;
    final positionAt = mesh.layout.floatOffsetOf(VertexLayout.position.name);
    final jointsAt = mesh.layout.floatOffsetOf(VertexLayout.joints.name);
    final weightsAt = mesh.layout.floatOffsetOf(VertexLayout.weights.name);
    if (positionAt < 0 || jointsAt < 0 || weightsAt < 0) return null;

    final vertices = mesh.vertices;
    final count = stride == 0 ? 0 : vertices.length ~/ stride;
    if (_positions.length < count * 3) _positions = Float32List(count * 3);
    _vertexCount = count;

    final matrices = skeleton.matrices;
    final joints = skeleton.jointCount;

    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var maxZ = -double.infinity;

    for (var v = 0; v < count; v++) {
      final at = v * stride;
      final x = vertices[at + positionAt];
      final y = vertices[at + positionAt + 1];
      final z = vertices[at + positionAt + 2];

      var px = 0.0;
      var py = 0.0;
      var pz = 0.0;
      var total = 0.0;

      for (var i = 0; i < 4; i++) {
        final weight = vertices[at + weightsAt + i];
        if (weight == 0.0) continue;
        final joint = vertices[at + jointsAt + i].toInt();
        // A joint index past the end is a broken file, not a reason to throw
        // in the middle of a click: the influence is dropped and the weights
        // that remain are renormalised below, which leaves the vertex where
        // its other joints put it rather than at the origin.
        if (joint < 0 || joint >= joints) continue;

        final m = joint * 16;
        // Column-major, the storage `Matrix4` uses and the one the shader is
        // handed: element (row, column) lives at `column * 4 + row`.
        px +=
            weight *
            (matrices[m] * x +
                matrices[m + 4] * y +
                matrices[m + 8] * z +
                matrices[m + 12]);
        py +=
            weight *
            (matrices[m + 1] * x +
                matrices[m + 5] * y +
                matrices[m + 9] * z +
                matrices[m + 13]);
        pz +=
            weight *
            (matrices[m + 2] * x +
                matrices[m + 6] * y +
                matrices[m + 10] * z +
                matrices[m + 14]);
        total += weight;
      }

      // **Renormalised, unlike the shader, and deliberately.** The stage
      // divides by nothing because glTF promises the four weights sum to one
      // and a GPU has no cheap way to complain; here the sum is in hand, and
      // a vertex whose weights sum to 0.9 would otherwise be posed a tenth of
      // the way back towards the origin — which reads as a hole in the
      // silhouette exactly where a click lands.
      final out = v * 3;
      final double ox;
      final double oy;
      final double oz;
      if (total <= 0.0) {
        // Bound to nothing: the bind pose is where it is.
        ox = x;
        oy = y;
        oz = z;
      } else {
        ox = px / total;
        oy = py / total;
        oz = pz / total;
      }
      _positions[out] = ox;
      _positions[out + 1] = oy;
      _positions[out + 2] = oz;

      // **The box the posed mesh actually occupies, gathered on the way
      // through.** The caster rejects a near miss on a local box before it
      // touches a triangle, and the mesh's own box is the bind pose's — so
      // with a posed test that box is the wrong shape and would reject the
      // very rays this exists to catch. It cost one comparison a vertex to
      // have the right one.
      if (ox < minX) minX = ox;
      if (oy < minY) minY = oy;
      if (oz < minZ) minZ = oz;
      if (ox > maxX) maxX = ox;
      if (oy > maxY) maxY = oy;
      if (oz > maxZ) maxZ = oz;
    }

    if (count == 0) {
      _bounds = Aabb3();
    } else {
      _bounds = Aabb3.minMax(
        Vector3(minX, minY, minZ),
        Vector3(maxX, maxY, maxZ),
      );
    }

    _mesh = mesh;
    _skeleton = skeleton;
    _pose = skeleton.poseVersion;
    _update = skeleton.updateCount;
    return _positions;
  }

  /// How many vertices the last pose covered.
  int get vertexCount => _vertexCount;

  /// The box the last posed mesh occupies, in its own space.
  ///
  /// Not the mesh's own [MeshData] bounds, which describe the bind pose: this
  /// is what the caster's early rejection has to use, or it throws away the
  /// rays that the posing exists to catch.
  Aabb3 get bounds => _bounds;
  Aabb3 _bounds = Aabb3();
}
