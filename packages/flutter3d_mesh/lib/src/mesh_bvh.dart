/// A tree over an editable mesh's triangles, answering in faces.
///
/// **The triangles come from the layout plan, and the answers do not.** A
/// person points at a face; a ray hits a triangle; a five-sided face is three
/// triangles and none of them is the thing anybody selected. The plan already
/// knows which face each of its triangles was cut from, so this carries that
/// map and hands back faces.
///
/// **Indexed by the mesh's own vertices rather than the plan's rows.** A plan
/// splits a corner once per normal and once per texture seam — twenty-four rows
/// for a box's eight corners — and none of those splits mean anything to a ray.
/// Building over the mesh's vertices means one position per vertex, and it
/// means [refit] after a drag is a copy of the positions the mesh already
/// holds rather than a walk of the plan.
///
/// **Refit inside a drag, rebuild when the topology changes.** The tree's shape
/// goes stale as vertices move apart and queries slow down; what it never goes
/// is wrong, because every box is recomputed. `OpResult.topologyChanged` is
/// what a caller reads to know which of the two it needs, and it is the same
/// flag that says whether the plan itself has to be rebuilt.
library;

import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

import 'edit_mesh.dart';
import 'layout_plan.dart';
import 'selection.dart';

/// Where a ray met the mesh.
typedef MeshHit = ({int face, int triangle, double distance, Vector3 point});

/// A bounding-volume hierarchy over an [EditMesh], through a [MeshLayoutPlan].
final class MeshBvh {
  MeshBvh(EditMesh mesh, MeshLayoutPlan plan) {
    rebuild(mesh, plan);
  }

  late TriangleBvh _tree;
  late Int32List _faceOfTriangle;

  /// The tree underneath, for a caller that wants the triangle queries
  /// themselves — `view-09`'s overlay asks it for what is inside a box before
  /// deciding what to draw.
  TriangleBvh get triangles => _tree;

  /// How many triangles it indexes.
  int get triangleCount => _tree.indices.length ~/ 3;

  /// The face triangle number [triangle] was cut from.
  int faceOf(int triangle) => _faceOfTriangle[triangle];

  /// Builds the tree again from [plan], which must describe [mesh] as it is.
  ///
  /// What a topological edit needs. The plan is rebuilt first — it is the thing
  /// that knows the triangles — and this reads it.
  void rebuild(EditMesh mesh, MeshLayoutPlan plan) {
    final rows = plan.indices;
    final count = plan.triangleCount * 3;
    final indices = Uint32List(count);
    for (var i = 0; i < count; i++) {
      indices[i] = plan.gpuVertexToVertex[rows[i]];
    }
    _faceOfTriangle = Int32List.fromList(
      Int32List.sublistView(plan.triangleToFace, 0, plan.triangleCount),
    );
    _tree = TriangleBvh.fromArrays(_positionsOf(mesh), indices);
  }

  /// Recomputes every box from where the vertices are now.
  ///
  /// **Only when the topology did not change.** The triangles are the ones the
  /// plan named at build time; a face added since is not in the tree, and this
  /// will not put it there. `rebuild` is the answer to that, and a caller that
  /// cannot tell the two apart is a caller that has not read
  /// `OpResult.topologyChanged`.
  void refit(EditMesh mesh) {
    final positions = _tree.positions;
    final live = mesh.positions;
    final count = positions.length < live.length
        ? positions.length
        : live.length;
    positions.setRange(0, count, live);
    _tree.refit();
  }

  /// The nearest face [ray] hits.
  MeshHit? raycast(Ray ray, {double maxDistance = double.infinity}) {
    final hit = _tree.raycast(ray, maxDistance: maxDistance);
    if (hit == null) return null;
    return (
      face: _faceOfTriangle[hit.triangle],
      triangle: hit.triangle,
      distance: hit.distance,
      point: hit.point,
    );
  }

  /// The faces that may reach into [box].
  ///
  /// Conservative, because the tree is: what comes back is every face with a
  /// triangle whose own box overlaps. A caller that needs exactness — a
  /// rectangle selection — narrows it against the vertices, which is what
  /// `MeshPicker.inFrustum` does.
  Selection facesInAabb(Aabb3 box) {
    final found = <int>{};
    _tree.forEachInAabb(box, (int triangle) {
      found.add(_faceOfTriangle[triangle]);
    });
    return Selection.of(ElementLevel.face, found);
  }

  /// The faces that may reach into [frustum].
  Selection facesInFrustum(Frustum frustum) {
    final found = <int>{};
    _tree.forEachInFrustum(frustum, (int triangle) {
      found.add(_faceOfTriangle[triangle]);
    });
    return Selection.of(ElementLevel.face, found);
  }

  static Float32List _positionsOf(EditMesh mesh) =>
      Float32List.fromList(mesh.positions);
}
