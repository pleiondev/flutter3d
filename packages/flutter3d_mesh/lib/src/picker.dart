/// Turning where somebody pointed into what they meant.
///
/// **Three levels, three different questions, and only one of them is a
/// raycast.** A face is what a ray hits, and the tree answers that in
/// microseconds. A vertex and an edge are not hit by a ray at all — they have
/// no area — so what a person means by clicking near one is the nearest one
/// within some distance of the line they pointed along, which is a scan.
///
/// **The radius is in the world, not in pixels.** This package has no camera
/// and should not grow one: a viewport knows how many world units a dozen
/// pixels are at the depth it is looking, and it is the only thing that does.
///
/// **Scanning is the right cost here.** Finding the face under a click is a
/// tree walk because it happens on every mouse move; finding the nearest vertex
/// happens on a click, and a pass over 200 000 of them is a millisecond. A
/// caller that wants better narrows the mesh with [MeshBvh.facesInFrustum]
/// first and picks within that.
library;

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

import 'edit_mesh.dart';
import 'mesh_bvh.dart';
import 'selection.dart';

/// Picks elements of a mesh from where a ray points.
final class MeshPicker {
  const MeshPicker(this.mesh, this.bvh);

  final EditMesh mesh;
  final MeshBvh bvh;

  /// The face [ray] hits first, or [EditMesh.none].
  int faceAt(Ray ray, {double maxDistance = double.infinity}) =>
      bvh.raycast(ray, maxDistance: maxDistance)?.face ?? EditMesh.none;

  /// The vertex nearest the line [ray] runs along, within [radius] of it.
  ///
  /// **Nearest along the ray, not nearest to it.** Two vertices both within the
  /// radius, one in front of the other: the one in front is the one a person
  /// clicked, even if the one behind happens to sit a hair closer to the exact
  /// line. Ordering by distance to the line instead is what makes a click on a
  /// dense mesh select something on the far side of it.
  ///
  /// With [visibleOnly], a vertex behind the surface the ray hits is not
  /// offered — which is what somebody working on the front of a model expects,
  /// and the opposite of what somebody box-selecting through it does.
  int vertexNear(Ray ray, {required double radius, bool visibleOnly = false}) {
    final limit = _surfaceDepth(ray, visibleOnly, radius);
    var best = EditMesh.none;
    var nearest = double.infinity;
    final at = Vector3.zero();
    for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
      if (!mesh.isVertexAlive(vertex)) continue;
      mesh.positionOf(vertex, at);
      final depth = (at - ray.origin).dot(ray.direction);
      if (depth < 0 || depth > limit || depth >= nearest) continue;
      if (_distanceToRay(ray, at, depth) > radius) continue;
      nearest = depth;
      best = vertex;
    }
    return best;
  }

  /// The edge nearest the line [ray] runs along, within [radius] of it.
  ///
  /// The same rule as [vertexNear], measured to the segment rather than to a
  /// point: an edge seen end-on is as close as one seen across, and a person
  /// clicking either of them means the same thing.
  int edgeNear(Ray ray, {required double radius, bool visibleOnly = false}) {
    final limit = _surfaceDepth(ray, visibleOnly, radius);
    var best = EditMesh.none;
    var nearest = double.infinity;
    final from = Vector3.zero();
    final to = Vector3.zero();

    for (var face = 0; face < mesh.faceSlotCount; face++) {
      if (!mesh.isFaceAlive(face)) continue;
      mesh.forEachHalfEdge(face, (int half) {
        if (mesh.edgeOf(half) != half) return;
        mesh.positionOf(mesh.originOf(half), from);
        mesh.positionOf(mesh.originOf(mesh.nextOf(half)), to);
        final near = _rayToSegment(ray, from, to);
        if (near.depth < 0 || near.depth > limit) return;
        if (near.gap > radius || near.depth >= nearest) return;
        nearest = near.depth;
        best = half;
      });
    }
    return best;
  }

  /// Everything of [level] inside [frustum], which is what a rectangle drag
  /// means.
  ///
  /// **A vertex is in when it is in; an edge or a face is in when all of it
  /// is.** The same rule `Selection.convertedTo` uses, and the reason is the
  /// same: a person who drags a box round part of a model and switches level
  /// expects the region they marked out, not the region plus everything
  /// hanging off its edge.
  Selection inFrustum(Frustum frustum, ElementLevel level) {
    final at = Vector3.zero();
    final inside = <int>[
      for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++)
        if (mesh.isVertexAlive(vertex) &&
            frustum.containsVector3(mesh.positionOf(vertex, at)))
          vertex,
    ];
    final vertices = Selection.of(ElementLevel.vertex, inside);
    return level == ElementLevel.vertex
        ? vertices
        : vertices.convertedTo(mesh, level);
  }

  /// How far along the ray the surface is, or infinity when nothing blocks.
  double _surfaceDepth(Ray ray, bool visibleOnly, double radius) {
    if (!visibleOnly) return double.infinity;
    final hit = bvh.raycast(ray);
    // A vertex *on* the surface the ray hit is in front of it by a hair or
    // behind it by one, depending on where in the face the ray landed; the
    // radius is the slack that keeps a corner of the very face somebody
    // clicked from being called hidden by it.
    return hit == null ? double.infinity : hit.distance + radius;
  }

  double _distanceToRay(Ray ray, Vector3 point, double depth) {
    final on = ray.origin + ray.direction * depth;
    return (point - on).length;
  }

  /// The closest approach between the ray and the segment, as how far along the
  /// ray it happens and how wide the gap is there.
  ({double depth, double gap}) _rayToSegment(
    Ray ray,
    Vector3 from,
    Vector3 to,
  ) {
    final along = to - from;
    final between = ray.origin - from;
    final dd = ray.direction.dot(ray.direction);
    final de = ray.direction.dot(along);
    final ee = along.dot(along);
    final dw = ray.direction.dot(between);
    final ew = along.dot(between);

    final denominator = dd * ee - de * de;
    // Parallel, or a segment of no length: anywhere on it is as good, so the
    // end the caller gave first answers, and the clamp below keeps it on the
    // segment either way.
    var s = denominator.abs() < 1e-12 ? 0.0 : (dd * ew - de * dw) / denominator;
    s = s.clamp(0.0, 1.0);

    final on = from + along * s;
    final depth = (on - ray.origin).dot(ray.direction);
    final gap = (on - (ray.origin + ray.direction * depth)).length;
    return (depth: depth, gap: gap);
  }
}
