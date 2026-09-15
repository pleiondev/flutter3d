/// Casting a weight-paint brush's ray against what a stroke actually needs
/// to hit: the mesh's current POSED shape, not its rest pose — `anim-10`'s
/// picking half, closed by `S5`.
///
/// **Posed from the engine's own live joints, not the document's.**
/// `flutter3d_model_core`'s own `paintWeights` (`paint_weights.dart`) already
/// poses a vertex to hit-test a sample, but it reads `worldTransformOf`
/// against the *document* — the joint as `ModelHistory` currently has it.
/// `ui/bend_slider_bar.dart` bends a joint's live `SceneNode` directly,
/// deliberately outside `ModelHistory` (see its own class comment), so a
/// brush that hit-tested against the document would miss a pose bent purely
/// to judge the paint job. [buildPosedBrushSurface] reads the engine's own
/// [Skeleton.joints] instead — the same live nodes `BendSliderBar` turns —
/// so a stroke lands where the picture already shows the mesh to be.
///
/// **Built fresh on every pointer-down, and not touched again mid-stroke.**
/// `paint_weights.dart`'s own posed-position snapshot freezes every vertex
/// before the first sample writes anything, for the reason its own doc
/// comment gives: a stroke that kept re-posing itself off weights it was
/// still painting could pull its own targets out of reach mid-drag.
/// Building the tree once at the start of a drag, and never refitting it
/// mid-stroke, is the UI's own half of that same rule.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' show Skeleton;
import 'package:flutter3d_geometry/flutter3d_geometry.dart' show TriangleBvh;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart'
    show ProjectSkeleton;
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;

/// A triangle tree over [mesh]'s current posed surface: [skeleton]'s own
/// live joints skin each vertex the same way the shader would —
/// `jointWorld · inverseBind · rest`, summed by [mesh]'s own stored weights.
///
/// [skeleton] and [projectSkeleton] must name the same rig in the same
/// order — `scene_sync.dart`'s own `Skeleton(joints: [nodeOf(id)…])`, built
/// straight off a `ProjectSkeleton.joints`, already guarantees that for
/// whatever `SceneSync` is tracking.
///
/// The layout the plan is built with is not [mesh]'s own — a plan's row
/// count is a question about topology and smoothing, not about which
/// attributes a row carries, so [VertexLayout.standard]'s default plan maps
/// back to the same vertices `VertexLayout.skinned` would, at a fraction of
/// the bookkeeping.
TriangleBvh buildPosedBrushSurface({
  required EditMesh mesh,
  required Skeleton skeleton,
  required ProjectSkeleton projectSkeleton,
}) {
  final plan = MeshLayoutPlan()..build(mesh);
  final rows = plan.indices;
  final indices = Uint32List(rows.length);
  for (var i = 0; i < rows.length; i++) {
    indices[i] = plan.gpuVertexToVertex[rows[i]];
  }

  final jointWorlds = <Matrix4>[
    for (final joint in skeleton.joints) joint.worldMatrix,
  ];
  final positions = Float32List(mesh.vertexSlotCount * 3);
  final rest = Vector3.zero();
  final blended = Vector3.zero();
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    if (!mesh.isVertexAlive(v)) continue;
    mesh.positionOf(v, rest);
    final pairs = weightsOf(mesh, v);
    // A vertex with no real, stored weight at all — the same edge case
    // `paint_weights.dart`'s own posed-position reader guards — poses at
    // its own rest position rather than at the origin every joint's own
    // identity-weighted blend would otherwise land it on.
    if (pairs.isEmpty) {
      positions[v * 3] = rest.x;
      positions[v * 3 + 1] = rest.y;
      positions[v * 3 + 2] = rest.z;
      continue;
    }
    blended.setZero();
    for (final pair in pairs) {
      if (pair.joint < 0 || pair.joint >= jointWorlds.length) continue;
      final skin = Matrix4.copy(jointWorlds[pair.joint])
        ..multiply(projectSkeleton.inverseBindMatrices[pair.joint]);
      blended.addScaled(skin.transformed3(Vector3.copy(rest)), pair.weight);
    }
    positions[v * 3] = blended.x;
    positions[v * 3 + 1] = blended.y;
    positions[v * 3 + 2] = blended.z;
  }

  return TriangleBvh.fromArrays(positions, indices);
}

/// The real mesh vertex nearest [point] among [triangle]'s own three
/// corners of [surface] — what "the vertex under the brush" means once a
/// raycast only ever answers with a triangle and a point somewhere inside
/// it, for the influences card `ui/weight_paint_panel.dart` shows.
int nearestVertexOfTriangle(TriangleBvh surface, int triangle, Vector3 point) {
  var best = surface.indices[triangle * 3];
  var bestDistance = double.infinity;
  for (var corner = 0; corner < 3; corner++) {
    final vertex = surface.indices[triangle * 3 + corner];
    final dx = surface.positions[vertex * 3] - point.x;
    final dy = surface.positions[vertex * 3 + 1] - point.y;
    final dz = surface.positions[vertex * 3 + 2] - point.z;
    final distance = dx * dx + dy * dy + dz * dz;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = vertex;
    }
  }
  return best;
}
